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

    /// Status refreshes run alongside user staging and commits; skip the opportunistic
    /// index refresh so they never hold `index.lock`.
    nonisolated static var statusReadEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        return environment
    }

    func trackedStatusCounts(in repositoryURL: URL) async -> (staged: Int, unstaged: Int) {
        let output = (try? await runGit(
            arguments: ["status", "--porcelain", "--untracked-files=no"],
            in: repositoryURL,
            environment: Self.statusReadEnvironment
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
        try await statusSnapshot(for: repositoryURL).status
    }

    /// Returns the status together with the object IDs porcelain v2 reports per path
    /// (HEAD/index blobs, or the conflict stages), so callers can tell whether a
    /// file's content changed between refreshes without running extra git commands.
    func statusSnapshot(for repositoryURL: URL) async throws -> GitStatusSnapshot {
        let output = try await runGit(
            arguments: ["status", "--porcelain=v2", "-z", "--untracked-files=all"],
            in: repositoryURL,
            environment: Self.statusReadEnvironment
        )
        var staged: [StatusFile] = []
        var unstaged: [StatusFile] = []
        var untracked: [StatusFile] = []
        var objectIDs: [String: String] = [:]

        var records = output.split(separator: "\0").makeIterator()
        while let record = records.next() {
            // Porcelain v2 records: `1 XY sub mH mI mW hH hI path`,
            // `2 XY sub mH mI mW hH hI Xscore path` (source path in the next record),
            // `u XY sub m1 m2 m3 mW h1 h2 h3 path`, `? path`, `! path`.
            guard let entry = Self.parsePorcelainV2Record(record, nextRecord: { records.next() }) else { continue }
            let indexStatus = entry.indexStatus
            let worktreeStatus = entry.worktreeStatus
            let path = entry.path
            let originalPath = entry.originalPath
            if !entry.objectIDs.isEmpty {
                objectIDs[path] = entry.objectIDs.joined(separator: " ")
            }

            let indexChar = indexStatus
            let worktreeChar = worktreeStatus

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

        return GitStatusSnapshot(
            status: GitStatus(staged: finalStaged, unstaged: finalUnstaged, untracked: finalUntracked),
            objectIDs: objectIDs
        )
    }

    private struct PorcelainV2Entry {
        let indexStatus: Character
        let worktreeStatus: Character
        let path: String
        let originalPath: String?
        let objectIDs: [Substring]
    }

    private static func parsePorcelainV2Record(
        _ record: Substring,
        nextRecord: () -> Substring?
    ) -> PorcelainV2Entry? {
        guard let kind = record.first else { return nil }
        let fieldCount: Int
        let objectIDRange: Range<Int>
        switch kind {
        case "?":
            return PorcelainV2Entry(
                indexStatus: "?",
                worktreeStatus: "?",
                path: String(record.dropFirst(2)),
                originalPath: nil,
                objectIDs: []
            )
        case "1":
            fieldCount = 8
            objectIDRange = 6..<8
        case "2":
            fieldCount = 9
            objectIDRange = 6..<8
        case "u":
            fieldCount = 10
            objectIDRange = 7..<10
        default:
            return nil
        }

        // Paths may contain spaces, so only split off the fixed leading fields.
        let fields = record.split(separator: " ", maxSplits: fieldCount, omittingEmptySubsequences: false)
        guard fields.count == fieldCount + 1, fields[1].count == 2 else { return nil }
        // v2 marks an unchanged side with `.` where v1 used a space.
        func statusCharacter(_ character: Character) -> Character {
            character == "." ? " " : character
        }
        return PorcelainV2Entry(
            indexStatus: statusCharacter(fields[1].first!),
            worktreeStatus: statusCharacter(fields[1].last!),
            path: String(fields[fieldCount]),
            originalPath: kind == "2" ? nextRecord().map(String.init) : nil,
            objectIDs: Array(fields[objectIDRange])
        )
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
