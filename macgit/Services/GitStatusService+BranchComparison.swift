// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService: ReferenceComparisonServing {
    func comparisonBranches(in repositoryURL: URL) async throws -> [ComparisonBranch] {
        try Task.checkCancellation()
        let output = try await runGit(arguments: [
            "for-each-ref", "--sort=refname", "--format=%(refname)%00%(symref)", "refs/heads/", "refs/remotes/"
        ], in: repositoryURL)
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[1].isEmpty else { return nil }
            return ComparisonBranch(ref: String(fields[0]))
        }
    }

    func comparisonSnapshot(base: String, target: String, branchesOnly: Bool, in repositoryURL: URL) async throws -> ReferenceComparisonSnapshot {
        let baseSHA = try await resolveComparisonRef(base, branchesOnly: branchesOnly, in: repositoryURL)
        let targetSHA = try await resolveComparisonRef(target, branchesOnly: branchesOnly, in: repositoryURL)
        try Task.checkCancellation()
        let counts = try await runGit(arguments: ["rev-list", "--left-right", "--count", "\(baseSHA)...\(targetSHA)", "--"], in: repositoryURL)
        let numbers = counts.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard numbers.count == 2 else { throw GitError.commandFailed("Could not read comparison commit counts.") }
        let mergeBases: [String]
        do {
            let output = try await runGit(arguments: ["merge-base", "--all", baseSHA, targetSHA], in: repositoryURL)
            mergeBases = output.split(whereSeparator: \.isWhitespace).map(String.init)
        } catch GitError.commandFailed(let message) where message.isEmpty {
            // git merge-base exits 1 with no output for unrelated histories.
            mergeBases = []
        }
        try Task.checkCancellation()
        return ReferenceComparisonSnapshot(base: baseSHA, target: targetSHA, mergeBases: mergeBases,
            baseOnlyCount: numbers[0], targetOnlyCount: numbers[1])
    }

    func resolveComparisonRef(_ ref: String, branchesOnly: Bool, in repositoryURL: URL) async throws -> String {
        try Task.checkCancellation()
        if branchesOnly {
            guard ref.hasPrefix("refs/heads/") || ref.hasPrefix("refs/remotes/") else {
                throw GitError.commandFailed("Select a local or remote-tracking branch.")
            }
            _ = try await runGit(arguments: ["check-ref-format", ref], in: repositoryURL)
            // Exact ref validation avoids interpreting suffixes such as ^ or : as revisions.
            _ = try await runGit(arguments: ["show-ref", "--verify", ref], in: repositoryURL)
        }
        let output = try await runGit(arguments: ["rev-parse", "--verify", "--end-of-options", "\(ref)^{commit}"], in: repositoryURL)
        let sha = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [40, 64].contains(sha.count), sha.allSatisfy(\.isHexDigit) else {
            throw GitError.commandFailed("Could not resolve the selected reference to a commit.")
        }
        return sha
    }

    func comparisonFiles(snapshot: ReferenceComparisonSnapshot, mode: ReferenceComparisonMode, in repositoryURL: URL) async throws -> [CommitFileChange] {
        try Task.checkCancellation()
        let base = try snapshot.diffBase(for: mode)
        let output = try await runGitRaw(arguments: [
            "--no-optional-locks", "diff", "--name-status", "-z", "--find-renames", "--no-ext-diff", "--no-textconv"
        ] + (snapshot.path == nil ? [base, snapshot.target] : snapshot.diffArguments) + ["--"], in: repositoryURL)
        let files = try Self.parseComparisonFiles(output)
        guard let path = snapshot.path else { return files }
        // Detect renames before filtering so moves across the folder boundary retain both paths.
        return files.filter { path.contains($0.path) || ($0.oldPath.map(path.contains) ?? false) }
    }

    nonisolated static func parseComparisonFiles(_ data: Data) throws -> [CommitFileChange] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var index = 0
        var result: [CommitFileChange] = []
        while index < fields.count, !fields[index].isEmpty {
            try Task.checkCancellation()
            let code = String(decoding: fields[index], as: UTF8.self)
            let hasOldPath = code.hasPrefix("R") || code.hasPrefix("C")
            let pathIndex = index + (hasOldPath ? 2 : 1)
            guard pathIndex < fields.count, !fields[pathIndex].isEmpty else {
                throw GitError.commandFailed("Could not read comparison file paths.")
            }
            let status = CommitFileStatus(rawValue: String(code.prefix(1))) ?? .modified
            result.append(CommitFileChange(path: String(decoding: fields[pathIndex], as: UTF8.self), status: status,
                oldPath: hasOldPath ? String(decoding: fields[index + 1], as: UTF8.self) : nil))
            index = pathIndex + 1
        }
        return result
    }

    func comparisonCommits(snapshot: ReferenceComparisonSnapshot, targetSide: Bool, skip: Int, limit: Int, in repositoryURL: URL) async throws -> [Commit] {
        try Task.checkCancellation()
        let range = targetSide ? "\(snapshot.base)..\(snapshot.target)" : "\(snapshot.target)..\(snapshot.base)"
        let output = try await runGit(arguments: [
            "log", "--topo-order", "--no-decorate", "--no-notes",
            "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad", "--date=iso-strict",
            "--max-count=\(max(1, min(limit, 200)))", "--skip=\(max(0, skip))", range, "--"
        ], in: repositoryURL)
        try Task.checkCancellation()
        return parseCommitLog(output)
    }

    func comparisonPatch(file: CommitFileChange, snapshot: ReferenceComparisonSnapshot, mode: ReferenceComparisonMode, in repositoryURL: URL) async throws -> ReferenceComparisonPatch {
        try Task.checkCancellation()
        let base = try snapshot.diffBase(for: mode)
        let paths = [file.oldPath, file.path].compactMap { $0 }
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        let output = try await runGitBounded(arguments: [
            "--no-optional-locks", "--literal-pathspecs", "diff", "--no-color", "--no-ext-diff", "--no-textconv", "--find-renames", "-U3",
        ] + (snapshot.path == nil ? [base, snapshot.target] : snapshot.diffArguments) + ["--"] + paths, in: repositoryURL, environment: environment, outputByteLimit: 2_000_000)
        try Task.checkCancellation()
        return ReferenceComparisonPatch(hunks: DiffParser.parse(output.text),
            isBinary: output.text.split(separator: "\n").contains { $0.hasPrefix("Binary files ") || $0 == "GIT binary patch" },
            isTruncated: output.isTruncated)
    }
}
