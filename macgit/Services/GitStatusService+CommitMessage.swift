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
import CryptoKit
import Foundation

nonisolated protocol CommitChangeSnapshotLoading: Sendable {
    func commitChangeSnapshot(
        in repositoryURL: URL,
        source: CommitChangeSource,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot

    func changesFingerprint(
        in repositoryURL: URL,
        source: CommitChangeSource
    ) async throws -> String
}

extension GitStatusService: CommitChangeSnapshotLoading {
    func commitChangeSnapshot(
        in repositoryURL: URL,
        source: CommitChangeSource,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        switch source {
        case .staged:
            try await stagedCommitChangeSnapshot(
                in: repositoryURL,
                characterBudget: characterBudget
            )
        case .workingTree:
            try await workingTreeCommitChangeSnapshot(
                in: repositoryURL,
                characterBudget: characterBudget
            )
        }
    }

    func changesFingerprint(
        in repositoryURL: URL,
        source: CommitChangeSource
    ) async throws -> String {
        switch source {
        case .staged:
            try await stagedChangesFingerprint(in: repositoryURL)
        case .workingTree:
            try await workingTreeChangesFingerprint(in: repositoryURL)
        }
    }

    private func stagedCommitChangeSnapshot(
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        let nameStatus = try await runGit(
            arguments: ["diff", "--cached", "--name-status", "--no-renames"],
            in: repositoryURL
        )
        guard !nameStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommitMessageGenerationError.noChanges(.staged)
        }

        let numberStats = try await runGit(
            arguments: ["diff", "--cached", "--numstat", "--no-renames"],
            in: repositoryURL
        )
        let patch = try await runGit(
            arguments: [
                "diff", "--cached", "--no-color", "--no-ext-diff", "--no-textconv",
                "--unified=3", "--no-renames",
            ],
            in: repositoryURL
        )
        let fingerprint = try await stagedChangesFingerprint(in: repositoryURL)
        let built = CommitMessageContextBuilder.build(
            nameStatus: nameStatus,
            numberStats: numberStats,
            patch: patch,
            characterBudget: characterBudget
        )
        return CommitChangeSnapshot(
            fingerprint: fingerprint,
            context: built.context,
            isTruncated: built.isTruncated
        )
    }

    private func stagedChangesFingerprint(in repositoryURL: URL) async throws -> String {
        try await runGit(arguments: ["write-tree"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func workingTreeCommitChangeSnapshot(
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        let trackedNameStatus = try await runGit(
            arguments: ["diff", "--name-status", "--no-renames"],
            in: repositoryURL
        )
        let trackedNumberStats = try await runGit(
            arguments: ["diff", "--numstat", "--no-renames"],
            in: repositoryURL
        )
        let trackedPatch = try await runGit(
            arguments: [
                "diff", "--no-color", "--no-ext-diff", "--no-textconv",
                "--unified=3", "--no-renames",
            ],
            in: repositoryURL
        )
        let untrackedPaths = try await untrackedPaths(in: repositoryURL)

        guard !trackedNameStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !untrackedPaths.isEmpty else {
            throw CommitMessageGenerationError.noChanges(.workingTree)
        }

        var nameStatusParts = [trackedNameStatus]
        var numberStatParts = [trackedNumberStats]
        var patchParts = [trackedPatch]
        var remainingUntrackedBudget = max(characterBudget - trackedPatch.count, 0)

        for path in untrackedPaths {
            nameStatusParts.append("A\t\(path)")
            let context = untrackedContext(
                for: path,
                in: repositoryURL,
                characterBudget: remainingUntrackedBudget
            )
            numberStatParts.append(context.numberStats)
            patchParts.append(context.patch)
            remainingUntrackedBudget = max(remainingUntrackedBudget - context.patch.count, 0)
        }

        let built = CommitMessageContextBuilder.build(
            nameStatus: nameStatusParts.filter { !$0.isEmpty }.joined(separator: "\n"),
            numberStats: numberStatParts.filter { !$0.isEmpty }.joined(separator: "\n"),
            patch: patchParts.filter { !$0.isEmpty }.joined(separator: "\n"),
            characterBudget: characterBudget
        )
        return CommitChangeSnapshot(
            fingerprint: try await workingTreeChangesFingerprint(in: repositoryURL),
            context: built.context,
            isTruncated: built.isTruncated
        )
    }

    private func workingTreeChangesFingerprint(in repositoryURL: URL) async throws -> String {
        let trackedPatch = try await runGit(
            arguments: ["diff", "--binary", "--no-ext-diff", "--no-textconv"],
            in: repositoryURL
        )
        let status = try await runGit(
            arguments: ["status", "--porcelain", "--untracked-files=all"],
            in: repositoryURL
        )
        var untrackedHashes: [String] = []
        for path in try await untrackedPaths(in: repositoryURL) {
            let hash = try await runGit(
                arguments: ["hash-object", "--no-filters", "--", path],
                in: repositoryURL
            )
            untrackedHashes.append(hash)
        }
        let fingerprintInput = ([status, trackedPatch] + untrackedHashes).joined(separator: "\n")
        return SHA256.hash(data: Data(fingerprintInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func untrackedPaths(in repositoryURL: URL) async throws -> [String] {
        let output = try await runGit(
            arguments: ["ls-files", "--others", "--exclude-standard"],
            in: repositoryURL
        )
        return output.split(separator: "\n").map(String.init)
    }

    private func untrackedContext(
        for path: String,
        in repositoryURL: URL,
        characterBudget: Int
    ) -> (numberStats: String, patch: String) {
        let fileURL = repositoryURL.appendingPathComponent(path)
        guard characterBudget > 0,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return ("-\t-\t\(path)", "diff --git a/\(path) b/\(path)\n[Untracked file content omitted]")
        }
        defer { try? handle.close() }

        let byteBudget = max(characterBudget * 2, 1)
        guard let data = try? handle.read(upToCount: byteBudget + 1),
              !data.contains(0) else {
            return ("-\t-\t\(path)", "diff --git a/\(path) b/\(path)\n[Binary untracked file]")
        }

        let wasTruncated = data.count > byteBudget
        let visibleData = data.prefix(byteBudget)
        let content = String(decoding: visibleData, as: UTF8.self)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let addedLines = lines.map { "+\($0)" }.joined(separator: "\n")
        let truncationNote = wasTruncated ? "\n[Additional untracked content omitted]" : ""
        let patch = """
            diff --git a/\(path) b/\(path)
            new file mode 100644
            --- /dev/null
            +++ b/\(path)
            @@ -0,0 +1,\(lines.count) @@
            \(addedLines)\(truncationNote)
            """
        return ("\(lines.count)\t0\t\(path)", patch)
    }
}
