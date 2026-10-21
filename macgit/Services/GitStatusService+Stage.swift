//
//  GitStatusService+Stage.swift
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
    func stageAllChanges(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["add", "--all"], in: repositoryURL)
    }

    func stage(file: StatusFile, in repositoryURL: URL) async throws {
        if let originalPath = file.originalPath {
            try await stageRename(file: file, originalPath: originalPath, in: repositoryURL)
        } else {
            _ = try await runGit(arguments: ["add", file.path], in: repositoryURL)
        }
    }

    func unstage(file: StatusFile, in repositoryURL: URL) async throws {
        // Resetting only the new path would leave the old path as a staged
        // deletion, so the user would see a confusing "added new file +
        // deleted old file" pair instead of the original rename row. We pass
        // both paths so the index returns to the worktree state.
        var arguments = ["reset", "HEAD", "--", file.path]
        if let originalPath = file.originalPath {
            arguments.append(originalPath)
        }
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func stageAll(files: [StatusFile], in repositoryURL: URL) async throws {
        guard !files.isEmpty else { return }

        var addArguments = ["add", "--"]
        var renameOriginals: [String] = []
        for file in files {
            addArguments.append(file.path)
            if let original = file.originalPath {
                renameOriginals.append(original)
            }
        }
        _ = try await runGit(arguments: addArguments, in: repositoryURL)

        if !renameOriginals.isEmpty {
            var rmArguments = ["rm", "--cached", "--"]
            rmArguments.append(contentsOf: renameOriginals)
            _ = try await runGit(arguments: rmArguments, in: repositoryURL)
        }
    }

    func unstageAll(files: [StatusFile], in repositoryURL: URL) async throws {
        guard !files.isEmpty else { return }
        var arguments = ["reset", "HEAD", "--"]
        for file in files {
            arguments.append(file.path)
            if let original = file.originalPath {
                arguments.append(original)
            }
        }
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func stopTracking(file: StatusFile, in repositoryURL: URL) async throws {
        let trackedPath = file.originalPath ?? file.path
        _ = try await runGit(arguments: ["rm", "--cached", "--", trackedPath], in: repositoryURL)
    }

    private func stageRename(file: StatusFile, originalPath: String, in repositoryURL: URL) async throws {
        // `git add <newpath>` alone leaves the old path untouched in the
        // index, which Git reads as "added new + missing tracked" rather
        // than a rename. Removing the old entry from the index with
        // `git rm --cached` (not plain `git rm`: the old file is already
        // gone from the worktree) is what produces a proper `R` row in
        // `git status`.
        _ = try await runGit(arguments: ["add", file.path], in: repositoryURL)
        _ = try await runGit(arguments: ["rm", "--cached", originalPath], in: repositoryURL)
    }

    // MARK: - Hunk / Line Operations

    func stage(hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        guard file.status != .untracked else {
            throw GitError.commandFailed("Cannot stage hunk for untracked file")
        }
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, cached: true)
    }

    func discard(hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        guard file.status != .untracked else {
            throw GitError.commandFailed("Cannot discard hunk for untracked file")
        }
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, reverse: true)
    }

    func stage(lines: [DiffLine], hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        guard file.status != .untracked else {
            throw GitError.commandFailed("Cannot stage lines for untracked file")
        }
        let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, cached: true)
    }

    func discard(lines: [DiffLine], hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        guard file.status != .untracked else {
            throw GitError.commandFailed("Cannot discard lines for untracked file")
        }
        let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, reverse: true)
    }

    func unstage(hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, cached: true, reverse: true)
    }

    func unstage(lines: [DiffLine], hunk: DiffHunk, file: StatusFile, in repositoryURL: URL) async throws {
        let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file.path)
        try await applyPatch(patch, in: repositoryURL, cached: true, reverse: true)
    }

    // MARK: - Patch Helpers

    func applyPatch(_ patch: String, in repositoryURL: URL, cached: Bool = false, reverse: Bool = false) async throws {
        var arguments = ["apply"]
        if cached { arguments.append("--cached") }
        if reverse { arguments.append("--reverse") }
        arguments.append("-")

        let context = try await gitExecutionContext()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: context.executable)
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        task.environment = context.environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = stderr

        let startedAt = Date.now
        do {
            try await runPatchProcess(task, patch: patch, stdin: stdin, stderr: stderr, context: context, repositoryURL: repositoryURL)
        } catch {
            await Self.recordAudit(arguments: arguments, directory: repositoryURL, startedAt: startedAt,
                                   standardOutput: nil, standardError: nil, error: error)
            throw error
        }
        await Self.recordAudit(arguments: arguments, directory: repositoryURL, startedAt: startedAt,
                               standardOutput: nil, standardError: nil, error: nil)
    }

    private func runPatchProcess(
        _ task: Process,
        patch: String,
        stdin: Pipe,
        stderr: Pipe,
        context: (executable: String, environment: [String: String]),
        repositoryURL: URL
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.terminationHandler = { process in
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errData, encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: GitError.commandFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    continuation.resume(returning: ())
                }
            }
            do {
                try task.run()
                if let data = patch.data(using: .utf8) {
                    stdin.fileHandleForWriting.write(data)
                }
                stdin.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(throwing: gitLaunchError(
                    error,
                    executable: context.executable,
                    directory: repositoryURL
                ))
            }
        }
    }

}
