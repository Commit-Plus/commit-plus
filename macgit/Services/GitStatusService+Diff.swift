//
//  GitStatusService+Diff.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation

extension GitStatusService {
    func diff(for file: String, in commit: String, in repositoryURL: URL) async -> [DiffHunk] {
        if isStashRef(commit) {
            let output = (try? await runGit(arguments: ["diff", "--no-color", "-U3", "\(commit)^1", commit, "--", file], in: repositoryURL)) ?? ""
            return DiffParser.parse(output)
        }

        let output = (try? await runGit(arguments: ["show", "--no-color", "--first-parent", "-p", commit, "--", file], in: repositoryURL)) ?? ""
        // Strip the commit header; diff starts at "diff --git"
        guard let diffStart = output.range(of: "diff --git") else { return [] }
        let diffText = String(output[diffStart.lowerBound...])
        return DiffParser.parse(diffText)
    }

    func diff(for file: StatusFile, in repositoryURL: URL) async throws -> [DiffHunk] {
        // Untracked file → read directly and show all lines as added (green)
        if file.status == .untracked {
            let fileURL = repositoryURL.appendingPathComponent(file.path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            let diffLines = lines.enumerated().map { index, line in
                DiffLine(oldLineNumber: nil, newLineNumber: index + 1, text: String(line), type: .added)
            }
            return [DiffHunk(header: "@@ -0,0 +1,\(lines.count) @@", lines: diffLines)]
        }

        // Deleted file → get old content from HEAD and show all lines as removed (red)
        if file.status == .deleted {
            let output = try await runGit(arguments: ["show", "HEAD:\(file.path)"], in: repositoryURL)
            let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
            let diffLines = lines.enumerated().map { index, line in
                DiffLine(oldLineNumber: index + 1, newLineNumber: nil, text: String(line), type: .removed)
            }
            return [DiffHunk(header: "@@ -1,\(lines.count) +0,0 @@", lines: diffLines)]
        }

        // Normal diff for modified/renamed/staged files
        let isStaged = file.status == .staged || file.status == .added || file.status == .renamed
        var arguments = ["diff", "--no-color", "-U3"]
        if isStaged {
            arguments.append("--cached")
        }
        arguments.append("--")
        arguments.append(file.path)

        let output = try await runGit(arguments: arguments, in: repositoryURL)
        return DiffParser.parse(output)
    }

    /// Reads the committed blob and expands the patch to include all unchanged lines.
    func fullFilePreview(
        for file: CommitFileChange,
        in commit: String,
        in repositoryURL: URL
    ) async throws -> [DiffLine] {
        let ref = file.status == .deleted ? "\(commit)^1" : commit
        let data = try await showFile(at: file.path, ref: ref, in: repositoryURL)
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw GitError.commandFailed("This file is binary or is not UTF-8 text.")
        }
        let output = try await runGit(arguments: [
            "show", "--format=", "--no-color", "--no-ext-diff", "--no-textconv",
            "--first-parent", "--follow", "--find-renames", "--unified=2147483647",
            commit, "--", file.path
        ], in: repositoryURL)
        let lines = DiffParser.parse(output).flatMap(\.lines).filter {
            $0.oldLineNumber != nil || $0.newLineNumber != nil
        }
        if !lines.isEmpty { return lines }

        // Mode-only changes and pure renames have no patch, but still have content.
        var sourceLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if sourceLines.last?.isEmpty == true { sourceLines.removeLast() }
        return sourceLines.enumerated().map { index, text in
            DiffLine(oldLineNumber: index + 1, newLineNumber: index + 1,
                     text: String(text), type: .context)
        }
    }

    func showFile(at path: String, ref: String, in repositoryURL: URL) async throws -> Data {
        try await runGitRaw(arguments: ["show", "\(ref):\(path)"], in: repositoryURL)
    }

    func indexFile(at path: String, in repositoryURL: URL) async throws -> Data {
        try await runGitRaw(arguments: ["show", ":\(path)"], in: repositoryURL)
    }

    func changedFiles(in commit: String, in repositoryURL: URL) async -> [CommitFileChange] {
        let output = (try? await runGit(arguments: ["show", "--name-status", "--first-parent", "--format=", commit], in: repositoryURL)) ?? ""
        var changes: [CommitFileChange] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            let statusCode = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let path: String
            if (statusCode.hasPrefix("R") || statusCode.hasPrefix("C")) && parts.count >= 3 {
                path = String(parts[2])
            } else {
                path = String(parts[1])
            }

            let status: CommitFileStatus
            switch statusCode.prefix(1) {
            case "A": status = .added
            case "M": status = .modified
            case "D": status = .deleted
            case "R": status = .renamed
            case "C": status = .copied
            default: status = .modified
            }
            changes.append(CommitFileChange(path: path, status: status))
        }
        return changes
    }

    func changedFiles(from baseRef: String, to targetRef: String, in repositoryURL: URL) async -> [CommitFileChange] {
        let output = (try? await runGit(
            arguments: ["diff", "--name-status", "--no-renames", baseRef, targetRef],
            in: repositoryURL
        )) ?? ""

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }

            let status: CommitFileStatus
            switch parts[0].first {
            case "A": status = .added
            case "D": status = .deleted
            case "R": status = .renamed
            case "C": status = .copied
            default: status = .modified
            }
            return CommitFileChange(path: parts[1], status: status)
        }
    }

    func pullRequestChangedFileCount(
        sourceBranch: String,
        targetBranch: String,
        remoteName: String?,
        in repositoryURL: URL
    ) async throws -> Int {
        let references = try await pullRequestComparisonReferences(
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            remoteName: remoteName,
            in: repositoryURL
        )

        let output = try await runGitRaw(
            arguments: [
                "diff",
                "--name-only",
                "-z",
                "--find-renames",
                "\(references.target)...\(references.source)",
                "--",
            ],
            in: repositoryURL
        )
        return output.split(separator: 0).count
    }

    func pullRequestChangedFiles(
        sourceBranch: String,
        targetBranch: String,
        remoteName: String?,
        in repositoryURL: URL
    ) async throws -> [CommitFileChange] {
        let references = try await pullRequestComparisonReferences(
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            remoteName: remoteName,
            in: repositoryURL
        )
        let output = try await runGit(
            arguments: [
                "diff",
                "--name-status",
                "--find-renames",
                "\(references.target)...\(references.source)",
                "--",
            ],
            in: repositoryURL
        )

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 2 else { return nil }
            let statusCode = parts[0]
            let path = (statusCode.hasPrefix("R") || statusCode.hasPrefix("C")) && parts.count >= 3
                ? parts[2]
                : parts[1]
            let status: CommitFileStatus
            switch statusCode.first {
            case "A": status = .added
            case "D": status = .deleted
            case "R": status = .renamed
            case "C": status = .copied
            default: status = .modified
            }
            return CommitFileChange(path: path, status: status)
        }
    }

    func pullRequestComparison(
        sourceBranch: String,
        targetBranch: String,
        remoteName: String?,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> RepositoryAIRefComparison {
        let references = try await pullRequestComparisonReferences(
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            remoteName: remoteName,
            in: repositoryURL
        )
        guard let base = RepositoryAIRef(references.target),
              let head = RepositoryAIRef(references.source) else {
            throw RepositoryAIError.invalidRefReference
        }
        return try await compareRefs(
            base: base,
            head: head,
            in: repositoryURL,
            characterBudget: characterBudget
        )
    }

    func pullRequestComparisonFingerprint(
        sourceBranch: String,
        targetBranch: String,
        remoteName: String?,
        in repositoryURL: URL
    ) async throws -> String {
        try await pullRequestComparison(
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            remoteName: remoteName,
            in: repositoryURL,
            characterBudget: 1_000
        ).fingerprint
    }

    func pullRequestDiff(
        for file: String,
        sourceBranch: String,
        targetBranch: String,
        remoteName: String?,
        in repositoryURL: URL
    ) async throws -> [DiffHunk] {
        let references = try await pullRequestComparisonReferences(
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            remoteName: remoteName,
            in: repositoryURL
        )
        let output = try await runGit(
            arguments: [
                "diff",
                "--no-color",
                "-U3",
                "\(references.target)...\(references.source)",
                "--",
                file,
            ],
            in: repositoryURL
        )
        return DiffParser.parse(output)
    }

    private func pullRequestComparisonReferences(
        sourceBranch: String,
        targetBranch: String,
        remoteName: String?,
        in repositoryURL: URL
    ) async throws -> (source: String, target: String) {
        let sourceRef = "refs/heads/\(sourceBranch)"
        guard await gitReferenceExists(sourceRef, in: repositoryURL) else {
            throw GitError.commandFailed("Could not find source branch '\(sourceBranch)'.")
        }

        let remoteTargetRef = remoteName.map { "refs/remotes/\($0)/\(targetBranch)" }
        let localTargetRef = "refs/heads/\(targetBranch)"
        if let remoteTargetRef, await gitReferenceExists(remoteTargetRef, in: repositoryURL) {
            return (sourceRef, remoteTargetRef)
        }
        guard await gitReferenceExists(localTargetRef, in: repositoryURL) else {
            throw GitError.commandFailed("Could not find target branch '\(targetBranch)'.")
        }
        return (sourceRef, localTargetRef)
    }

    private func gitReferenceExists(_ reference: String, in repositoryURL: URL) async -> Bool {
        do {
            _ = try await runGit(
                arguments: ["rev-parse", "--verify", "--quiet", reference],
                in: repositoryURL
            )
            return true
        } catch {
            return false
        }
    }

    func diff(
        for file: String,
        from baseRef: String,
        to targetRef: String,
        in repositoryURL: URL
    ) async -> [DiffHunk] {
        let output = (try? await runGit(
            arguments: ["diff", "--no-color", "-U3", baseRef, targetRef, "--", file],
            in: repositoryURL
        )) ?? ""
        return DiffParser.parse(output)
    }

    func checkoutCommit(_ commit: String, force: Bool = false, in repositoryURL: URL) async throws {
        var arguments = ["checkout"]
        if force { arguments.append("-f") }
        arguments.append(commit)
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func cherryPickCommit(_ commit: String, in repositoryURL: URL) async throws {
        try await cherryPickCommits([commit], in: repositoryURL)
    }

    func cherryPickCommits(_ commits: [String], in repositoryURL: URL) async throws {
        guard !commits.isEmpty else {
            throw GitError.commandFailed("Select at least one commit to cherry-pick.")
        }
        _ = try await runGit(arguments: ["cherry-pick"] + commits, in: repositoryURL)
    }

    @discardableResult
    func cherryPickCommits(
        _ commits: [String],
        onto targetBranch: String,
        in repositoryURL: URL
    ) async throws -> GitCherryPickExecutionLocation {
        guard !commits.isEmpty else {
            throw GitError.commandFailed("Select at least one commit to cherry-pick.")
        }

        let currentBranch = await currentBranch(in: repositoryURL)
        if currentBranch == targetBranch {
            try await cherryPickCommits(commits, in: repositoryURL)
            return .currentWorkingCopy
        }

        if let existingWorktree = try await worktreePath(for: targetBranch, in: repositoryURL) {
            do {
                try await cherryPickCommits(commits, in: existingWorktree)
                return .existingWorktree(existingWorktree)
            } catch {
                throw await worktreeCherryPickError(
                    from: error,
                    path: existingWorktree,
                    kind: .existing
                )
            }
        }

        let temporaryWorktree = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("macgit-cherry-pick-\(UUID().uuidString)", isDirectory: true)
        _ = try await runGit(
            arguments: ["worktree", "add", temporaryWorktree.path, targetBranch],
            in: repositoryURL
        )

        do {
            try await cherryPickCommits(commits, in: temporaryWorktree)
        } catch {
            let cherryPickError = await worktreeCherryPickError(
                from: error,
                path: temporaryWorktree,
                kind: .temporary
            )
            if cherryPickError.isConflict {
                throw cherryPickError
            }

            let abortError = await cleanupError {
                _ = try await runGit(arguments: ["cherry-pick", "--abort"], in: temporaryWorktree)
            }
            do {
                _ = try await runGit(
                    arguments: ["worktree", "remove", temporaryWorktree.path, "--force"],
                    in: repositoryURL
                )
            } catch {
                let cleanupDetails = [abortError, error.localizedDescription]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                throw GitCherryPickWorktreeError(
                    path: temporaryWorktree,
                    kind: .temporary,
                    isConflict: false,
                    gitMessage: cherryPickError.gitMessage,
                    cleanupMessage: cleanupDetails
                )
            }

            throw error
        }

        do {
            _ = try await runGit(
                arguments: ["worktree", "remove", temporaryWorktree.path],
                in: repositoryURL
            )
        } catch {
            throw GitCherryPickWorktreeError(
                path: temporaryWorktree,
                kind: .temporary,
                isConflict: false,
                gitMessage: "Cherry-pick succeeded, but the temporary worktree could not be removed.",
                cleanupMessage: error.localizedDescription
            )
        }

        return .temporaryWorktree
    }

    private func worktreeCherryPickError(
        from error: Error,
        path: URL,
        kind: GitCherryPickWorktreeError.WorktreeKind
    ) async -> GitCherryPickWorktreeError {
        let message = error.localizedDescription
        let hasCherryPickHead = (try? await runGit(
            arguments: ["rev-parse", "--verify", "CHERRY_PICK_HEAD"],
            in: path
        )) != nil
        return GitCherryPickWorktreeError(
            path: path,
            kind: kind,
            isConflict: hasCherryPickHead || message.localizedCaseInsensitiveContains("conflict"),
            gitMessage: message,
            cleanupMessage: nil
        )
    }

    private func cleanupError(_ operation: () async throws -> Void) async -> String? {
        do {
            try await operation()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func mergeCommit(_ commit: String, noCommit: Bool = false, log: Bool = false, in repositoryURL: URL) async throws {
        var arguments = ["merge"]
        if noCommit { arguments.append("--no-commit") }
        if log { arguments.append("--log") }
        arguments.append(commit)
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func rebaseCommit(_ commit: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["rebase", commit], in: repositoryURL)
    }

    func resetToCommit(_ commit: String, mode: ResetMode, in repositoryURL: URL) async throws {
        let flag: String
        switch mode {
        case .soft: flag = "--soft"
        case .mixed: flag = "--mixed"
        case .hard: flag = "--hard"
        }
        _ = try await runGit(arguments: ["reset", flag, commit], in: repositoryURL)
    }

    func revertCommit(_ commit: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["revert", "--no-edit", commit], in: repositoryURL)
    }

    func inProgressOperation(in repositoryURL: URL) async -> GitInProgressOperation? {
        if let head = try? await runGit(arguments: ["rev-parse", "--verify", "CHERRY_PICK_HEAD"], in: repositoryURL),
           !head.isEmpty {
            return .cherryPick(head: head.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let head = try? await runGit(arguments: ["rev-parse", "--verify", "REVERT_HEAD"], in: repositoryURL),
           !head.isEmpty {
            return .revert(head: head.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let head = try? await runGit(arguments: ["rev-parse", "--verify", "MERGE_HEAD"], in: repositoryURL),
           !head.isEmpty {
            return .merge(head: head.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func continueMerge(in repositoryURL: URL) async throws {
        guard await isMergeInProgress(in: repositoryURL) else {
            throw GitError.commandFailed("No merge is in progress.")
        }
        _ = try await runGit(arguments: ["commit", "--no-edit"], in: repositoryURL)
    }

    func continueCherryPick(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["cherry-pick", "--continue"], in: repositoryURL)
    }

    func abortCherryPick(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["cherry-pick", "--abort"], in: repositoryURL)
    }

    func continueRevert(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["revert", "--continue"], in: repositoryURL)
    }

    func abortRevert(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["revert", "--abort"], in: repositoryURL)
    }

    func skipCherryPick(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["cherry-pick", "--skip"], in: repositoryURL)
    }

    func skipRevert(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["revert", "--skip"], in: repositoryURL)
    }

    func createTag(name: String, commit: String, annotated: Bool, message: String?, in repositoryURL: URL) async throws {
        var arguments = ["tag"]
        if annotated {
            arguments.append("-a")
        }
        arguments.append(name)
        if annotated, let message = message, !message.isEmpty {
            arguments.append("-m")
            arguments.append(message)
        }
        arguments.append(commit)
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    private func isStashRef(_ ref: String) -> Bool {
        ref.hasPrefix("stash@{")
    }
}

enum ResetMode {
    case soft, mixed, hard
}
