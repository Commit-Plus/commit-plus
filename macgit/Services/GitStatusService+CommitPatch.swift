// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CryptoKit

extension GitStatusService {
    func commitPatchUnavailableReasons(commit: String, in repositoryURL: URL) async throws -> [String: String] {
        let sha = try await resolveComparisonRef(commit, branchesOnly: false, in: repositoryURL)
        var reasons: [String: String] = [:]
        let stats = try await runGitRaw(arguments: ["diff-tree", "--root", "--no-commit-id", "--no-renames", "-r", "--numstat", "-z", sha], in: repositoryURL)
        for record in stats.split(separator: 0) {
            let fields = record.split(separator: 9, maxSplits: 2)
            if fields.count == 3, fields[0] == Data("-".utf8) {
                reasons[String(decoding: fields[2], as: UTF8.self)] = "Binary changes are not supported."
            }
        }
        let raw = try await runGitRaw(arguments: ["diff-tree", "--root", "--no-commit-id", "--no-renames", "-r", "--raw", "-z", sha], in: repositoryURL)
        let fields = raw.split(separator: 0)
        var index = 0
        while index + 1 < fields.count {
            let metadata = String(decoding: fields[index], as: UTF8.self).split(separator: " ")
            let path = String(decoding: fields[index + 1], as: UTF8.self)
            if metadata.prefix(2).contains(where: { $0.contains("160000") }) {
                reasons[path] = "Submodule changes are not supported."
            } else if metadata.prefix(2).contains(where: { $0.contains("120000") }) {
                reasons[path] = "Symbolic-link changes are not supported."
            }
            index += 2
        }
        return reasons
    }

    func prepareCommitPatch(_ request: CommitPatchRequest, in repositoryURL: URL) async throws -> PreparedCommitPatch {
        guard !request.files.isEmpty, request.lines == nil || request.files.count == 1 else {
            throw GitError.commandFailed("Select files or changed lines from one file.")
        }
        try await validateCommitPatchState(in: repositoryURL)
        let commit = try await resolveComparisonRef(request.commit, branchesOnly: false, in: repositoryURL)
        let ancestry = try await runGit(arguments: ["rev-list", "--parents", "-n", "1", commit], in: repositoryURL)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard ancestry.count <= 2 else {
            throw GitError.commandFailed("Selected changes from merge commits are not supported. Choose a non-merge commit.")
        }
        let parent: String
        if ancestry.count == 2 { parent = ancestry[1] }
        else {
            parent = try await runGit(arguments: ["hash-object", "-t", "tree", "/dev/null"], in: repositoryURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let allFiles = try Self.parseComparisonFiles(try await runGitRaw(arguments: [
            "diff", "--name-status", "-z", "--find-renames", parent, commit, "--"
        ], in: repositoryURL))
        let files = try request.files.map { selected in
            guard let file = allFiles.first(where: { $0.path == selected.path }) else {
                throw GitError.commandFailed("The selected files no longer match the commit.")
            }
            return file
        }
        guard Set(files.map(\.path)).count == files.count else {
            throw GitError.commandFailed("A file was selected more than once.")
        }
        let paths = Set(files.flatMap { [$0.oldPath, $0.path].compactMap { $0 } }).sorted()
        let fingerprint = try await commitPatchFingerprint(paths: paths, in: repositoryURL)
        let targetHead = try await runGit(arguments: ["rev-parse", "HEAD"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var reviewFiles: [CommitPatchReviewFile] = []
        for file in files {
            let refs = request.direction == .apply ? [parent, commit] : [commit, parent]
            let data = try await runGitRaw(arguments: [
                "--literal-pathspecs", "-c", "core.quotePath=true", "diff", "--no-color", "--no-ext-diff", "--no-textconv",
                "--no-relative", "--src-prefix=a/", "--dst-prefix=b/", "--find-renames", "--full-index", "--diff-algorithm=myers", "-U3"
            ] + refs + ["--"] + [file.oldPath, file.path].compactMap { $0 }, in: repositoryURL)
            guard let raw = String(data: data, encoding: .utf8), data.count <= 5_000_000 else {
                throw GitError.commandFailed("This patch is too large or is not UTF-8 text.")
            }
            let patch = try CommitPatchBuilder.build(raw: raw, selectedLines: request.lines, reversed: request.direction == .revert)
            reviewFiles.append(try await prepareCommitPatchReviewFile(file: file, patch: patch,
                base: refs[0], in: repositoryURL))
        }
        guard try await commitPatchFingerprint(paths: paths, in: repositoryURL) == fingerprint else {
            throw GitError.commandFailed("The working copy changed while preparing the patch. Try again.")
        }
        let branch = (try? await runGit(arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Detached HEAD"
        let resolved = CommitPatchRequest(commit: commit, files: files, direction: request.direction, lines: request.lines, scope: request.scope)
        var prepared = PreparedCommitPatch(request: resolved, repositoryURL: repositoryURL, parent: parent,
            targetBranch: branch, targetHead: targetHead, paths: paths, patch: "", fingerprint: fingerprint,
            reviewFiles: reviewFiles)
        prepared.rebuildPatch()
        return prepared
    }

    func applyCommitPatch(_ prepared: PreparedCommitPatch) async throws {
        guard !prepared.hasConflicts else {
            throw GitError.commandFailed("Resolve or skip the highlighted files before applying. No files have been changed.")
        }
        guard prepared.hasChanges else { return }
        try await executeCommitPatch(prepared.patch, reverse: false, in: prepared.repositoryURL, expected: prepared)
    }

    /// Also used for undo/redo. A rejected patch never creates .rej files or an in-progress merge.
    func applyCheckedWorkingTreePatch(_ patch: String, reverse: Bool, in repositoryURL: URL) async throws {
        try await executeCommitPatch(patch, reverse: reverse, in: repositoryURL, expected: nil)
    }

    private func executeCommitPatch(_ patch: String, reverse: Bool, in repositoryURL: URL, expected: PreparedCommitPatch?) async throws {
        let key = repositoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard activeCommitPatchRepositories.insert(key).inserted else {
            throw GitError.commandFailed("Another selected-patch operation is already running in this working copy.")
        }
        defer { activeCommitPatchRepositories.remove(key) }
        try await validateCommitPatchState(in: repositoryURL)
        try await runCommitPatch(patch, checkOnly: true, reverse: reverse, in: repositoryURL)
        if let expected,
           try await commitPatchFingerprint(paths: expected.paths, in: repositoryURL) != expected.fingerprint {
            throw GitError.commandFailed("The branch, index, or selected files changed after review. Close this sheet and review the changes again.")
        }
        try Task.checkCancellation()
        // Cancellation is allowed during preflight, but must not terminate Git halfway through writing files.
        try await Task { try await self.runCommitPatch(patch, checkOnly: false, reverse: reverse, in: repositoryURL) }.value
    }

    func runCommitPatch(_ patch: String, checkOnly: Bool, reverse: Bool, in repositoryURL: URL) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("commit-patch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("changes.patch")
        try Data(patch.utf8).write(to: url)
        var arguments = ["apply", "--whitespace=nowarn"]
        if checkOnly { arguments.append("--check") }
        if reverse { arguments.append("--reverse") }
        arguments += ["--", url.path]
        do { _ = try await runGit(arguments: arguments, in: repositoryURL) }
        catch {
            let message = checkOnly
                ? "The selected changes could not be applied cleanly. Your working copy has been preserved."
                : "Git could not finish applying the selected changes. Review the working copy before trying again."
            throw GitError.commandFailed("\(message)\n\n\(error.localizedDescription)")
        }
    }

    func validateCommitPatchState(in repositoryURL: URL) async throws {
        for name in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "sequencer", "index.lock"] {
            let path = try await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-path", name], in: repositoryURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: path) {
                throw GitError.commandFailed("Finish the current Git operation before applying selected changes.")
            }
        }
        let unmerged = try await runGitRaw(arguments: ["ls-files", "--unmerged", "-z"], in: repositoryURL)
        guard unmerged.isEmpty else { throw GitError.commandFailed("Resolve existing conflicts before applying selected changes.") }
    }

    func commitPatchFingerprint(paths: [String], in repositoryURL: URL) async throws -> String {
        var hash = SHA256()
        func append(_ data: Data) {
            hash.update(data: Data("\(data.count):".utf8))
            hash.update(data: data)
        }
        append(try await runGitRaw(arguments: ["rev-parse", "HEAD"], in: repositoryURL))
        append(Data(((try? await runGit(arguments: ["symbolic-ref", "--quiet", "HEAD"], in: repositoryURL)) ?? "detached").utf8))
        append(try await runGitRaw(arguments: ["ls-files", "--stage", "-z"], in: repositoryURL))
        for path in paths {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.split(separator: "/").contains(".git") else {
                throw GitError.commandFailed("The patch contains an unsafe path.")
            }
            let url = repositoryURL.appendingPathComponent(path)
            var componentURL = repositoryURL
            for component in path.split(separator: "/") {
                componentURL.appendPathComponent(String(component))
                if let attributes = try? FileManager.default.attributesOfItem(atPath: componentURL.path),
                   attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                    throw GitError.commandFailed("The selected path contains a symbolic link: \(path)")
                }
            }
            append(Data(path.utf8))
            if FileManager.default.fileExists(atPath: url.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw GitError.commandFailed("The selected path is not a regular file: \(path)")
                }
                append(Data("file:\(attributes[.posixPermissions] ?? 0)".utf8))
                append(try Data(contentsOf: url))
            } else { append(Data("missing".utf8)) }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
