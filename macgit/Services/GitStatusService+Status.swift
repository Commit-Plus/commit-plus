//
//  GitStatusService+Status.swift
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
    func uncommittedChangeCount(in repositoryURL: URL) async -> Int {
        let script = "\"$1\" status --porcelain -uall | /usr/bin/wc -l"
        guard let context = try? await gitExecutionContext() else { return 0 }
        let output = try? await runProcessRaw(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-o", "pipefail", "-c", script, "macgit-status-count", context.executable],
            in: repositoryURL,
            environment: context.environment
        )
        let text = output.flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(text ?? "") ?? 0
    }

    func trackedStatusCounts(in repositoryURL: URL) async -> (staged: Int, unstaged: Int) {
        let output = (try? await runGit(
            arguments: ["status", "--porcelain", "--untracked-files=no"],
            in: repositoryURL
        )) ?? ""

        var staged = 0
        var unstaged = 0

        for line in output.split(separator: "\n") where line.count >= 2 {
            let indexStatus = line.first!
            let worktreeStatus = line.dropFirst().first!

            if indexStatus != " " { staged += 1 }
            if worktreeStatus != " " { unstaged += 1 }
        }

        return (staged: staged, unstaged: unstaged)
    }

    func status(for repositoryURL: URL) async throws -> GitStatus {
        let output = try await runGit(arguments: ["status", "--porcelain", "--untracked-files=all"], in: repositoryURL)
        var staged: [StatusFile] = []
        var unstaged: [StatusFile] = []
        var untracked: [StatusFile] = []

        for line in output.split(separator: "\n") {
            let line = String(line)
            guard line.count >= 3 else { continue }
            let indexStatus = line.prefix(1)
            let worktreeStatus = line.dropFirst(1).prefix(1)
            let pathPart = String(line.dropFirst(3))

            // Parse renamed paths (R  old -> new)
            var path = pathPart
            var originalPath: String? = nil
            if indexStatus == "R" || worktreeStatus == "R" {
                let components = pathPart.split(separator: " -> ", maxSplits: 1)
                if components.count == 2 {
                    originalPath = String(components[0])
                    path = String(components[1])
                }
            }

            let indexChar = Character(String(indexStatus))
            let worktreeChar = Character(String(worktreeStatus))

            // Detect merge conflicts
            let isConflict = indexStatus == "U" || worktreeStatus == "U" ||
                             (indexStatus == "A" && worktreeStatus == "A") ||
                             (indexStatus == "D" && worktreeStatus == "D")

            if isConflict {
                let conflict = StatusFile(
                    path: path,
                    status: .conflict,
                    originalPath: originalPath
                )
                staged.append(conflict)
                unstaged.append(conflict)
                continue
            }

            // Index status -> staged
            switch indexChar {
            case "M", "A", "D", "R", "C":
                let status: FileStatus = (indexChar == "A") ? .added :
                                         (indexChar == "D") ? .deleted :
                                         (indexChar == "R") ? .renamed :
                                         (indexChar == "C") ? .added : .staged
                staged.append(StatusFile(path: path, status: status, originalPath: originalPath))
            default:
                break
            }

            // Worktree status -> unstaged or untracked
            switch worktreeChar {
            case "M", "D":
                let status: FileStatus = (worktreeChar == "D") ? .deleted : .modified
                unstaged.append(StatusFile(path: path, status: status, originalPath: originalPath))
            case "?":
                // Untracked folders that contain an embedded git repository
                // (leftover submodule checkouts, nested clones) are hidden,
                // matching other clients: staging one would silently register
                // it as a gitlink, and discarding would wipe a nested checkout.
                if path.hasSuffix("/"), Self.isEmbeddedGitRepository(at: path, in: repositoryURL) {
                    continue
                }
                untracked.append(StatusFile(path: path, status: .untracked, originalPath: nil))
            default:
                break
            }
        }

        let (finalStaged, finalUnstaged, finalUntracked) = Self.pairWorktreeRenames(
            staged: staged,
            unstaged: unstaged,
            untracked: untracked
        )

        return GitStatus(staged: finalStaged, unstaged: finalUnstaged, untracked: finalUntracked)
    }

    private static func isEmbeddedGitRepository(at path: String, in repositoryURL: URL) -> Bool {
        let marker = repositoryURL
            .appendingPathComponent(path)
            .appendingPathComponent(".git").path
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: marker, isDirectory: &isDirectory)
    }

    /// Coalesces worktree-level `D` entries with a same-basename partner in
    /// either the untracked list or the index's `A`/`M` slots into a single
    /// `.renamed` entry.
    ///
    /// `git status --porcelain` does not perform rename detection, so a file
    /// that is moved on disk shows up as a deletion at the old path plus a
    /// new entry at the new path. Where the new entry lives depends on how
    /// the move got into the repo:
    ///
    /// - Finder move / `git stash apply` of a previously-staged move: the
    ///   new file appears as `??` (untracked) and the old one as ` D`
    ///   (worktree deletion).
    /// - `git stash apply` of a move that was *never* staged, or a Finder
    ///   move followed by `git add` of just the new file: the new file
    ///   appears as `A ` (index added) and the old one as ` D`.
    ///
    /// Tower, Fork and Sourcetree collapse all of these into a single
    /// renamed row; we do the same by matching the worktree deletion with
    /// an untracked or index-added file of the same basename. The resulting
    /// entry keeps the new path as `path` and the old path as
    /// `originalPath`, matching the convention used by the index `R`
    /// parser above.
    static func pairWorktreeRenames(
        staged: [StatusFile],
        unstaged: [StatusFile],
        untracked: [StatusFile]
    ) -> (staged: [StatusFile], unstaged: [StatusFile], untracked: [StatusFile]) {
        var remainingStaged = staged
        var remainingUntracked = untracked
        var renamed: [StatusFile] = []

        let keptUnstaged: [StatusFile] = unstaged.compactMap { candidate in
            guard candidate.status == .deleted else { return candidate }
            let basename = candidate.displayName

            if let untrackedIdx = remainingUntracked.firstIndex(where: {
                $0.status == .untracked && $0.displayName == basename
            }) {
                let matched = remainingUntracked.remove(at: untrackedIdx)
                renamed.append(StatusFile(
                    path: matched.path,
                    status: .renamed,
                    originalPath: candidate.path
                ))
                return nil
            }

            if let stagedIdx = remainingStaged.firstIndex(where: {
                ($0.status == .added || $0.status == .staged) && $0.displayName == basename
            }) {
                let matched = remainingStaged.remove(at: stagedIdx)
                renamed.append(StatusFile(
                    path: matched.path,
                    status: .renamed,
                    originalPath: candidate.path
                ))
                return nil
            }

            return candidate
        }

        return (remainingStaged, keptUnstaged + renamed, remainingUntracked)
    }

    func hasConflicts(in repositoryURL: URL) async -> Bool {
        guard let status = try? await self.status(for: repositoryURL) else { return false }
        return status.staged.contains(where: { $0.status == .conflict })
            || status.unstaged.contains(where: { $0.status == .conflict })
            || status.untracked.contains(where: { $0.status == .conflict })
    }

    func discard(file: StatusFile, in repositoryURL: URL) async throws {
        if file.status == .untracked {
            // Remove untracked file from filesystem
            let fileURL = repositoryURL.appendingPathComponent(file.path)
            try FileManager.default.removeItem(at: fileURL)
        } else {
            _ = try await runGit(arguments: ["checkout", "--", file.path], in: repositoryURL)
        }
    }

    func remove(file: StatusFile, in repositoryURL: URL) async throws {
        if file.status == .untracked {
            let fileURL = repositoryURL.appendingPathComponent(file.path)
            try FileManager.default.removeItem(at: fileURL)
        } else {
            _ = try await runGit(arguments: ["rm", "-f", file.path], in: repositoryURL)
        }
    }

    func ignore(file: StatusFile, in repositoryURL: URL) async throws {
        try await ignore(file: file, pattern: file.path, in: repositoryURL)
    }

    func ignore(file: StatusFile, pattern: String, in repositoryURL: URL) async throws {
        let gitignoreURL = repositoryURL.appendingPathComponent(".gitignore")
        let entry = "\(pattern)\n"

        if FileManager.default.fileExists(atPath: gitignoreURL.path) {
            let handle = try FileHandle(forWritingTo: gitignoreURL)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try entry.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        }

        if file.status != .untracked {
            _ = try? await runGit(arguments: ["rm", "--cached", file.path], in: repositoryURL)
        }
    }

    func resolveConflict(file: StatusFile, in repositoryURL: URL, using: ConflictResolution) async throws {
        let flag = using == .ours ? "--ours" : "--theirs"
        _ = try await runGit(arguments: ["checkout", flag, "--", file.path], in: repositoryURL)
        _ = try await runGit(arguments: ["add", file.path], in: repositoryURL)
    }

    func conflictDocument(for file: StatusFile, in repositoryURL: URL) async throws -> ConflictResolutionDocument {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw GitError.commandFailed("Conflicted file could not be found on disk.")
        }

        let workingTreeContent = try String(contentsOf: fileURL, encoding: .utf8)
        let currentContent = try await runGit(arguments: ["show", ":2:\(file.path)"], in: repositoryURL)
        let incomingContent = try await runGit(arguments: ["show", ":3:\(file.path)"], in: repositoryURL)

        return try ConflictResolutionDocument.parse(
            workingTreeContent,
            currentContent: currentContent,
            incomingContent: incomingContent
        )
    }

    func resolveConflict(
        file: StatusFile,
        in repositoryURL: URL,
        with document: ConflictResolutionDocument
    ) async throws {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        try document.resolvedText.write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try await runGit(arguments: ["add", "--", file.path], in: repositoryURL)
    }

    func conflictStageFile(
        at path: String,
        stage: Int,
        in repositoryURL: URL
    ) async throws -> Data {
        try await runGitRaw(arguments: ["show", ":\(stage):\(path)"], in: repositoryURL)
    }

    func resetToCommit(file: StatusFile, commit: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["checkout", commit, "--", file.path], in: repositoryURL)
    }
}
