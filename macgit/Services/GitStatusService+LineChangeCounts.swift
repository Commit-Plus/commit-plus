// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func lineChangeCounts(for files: [StatusFile], staged: Bool, in repositoryURL: URL) async -> [String: FileLineChangeCount] {
        guard !files.isEmpty else { return [:] }
        var arguments = ["diff", "--numstat", "-z", "--find-renames", "--no-ext-diff", "--no-textconv"]
        if staged { arguments.append("--cached") }
        arguments.append("--")
        guard let data = try? await runGitRaw(arguments: arguments, in: repositoryURL) else { return [:] }
        let parsed = Self.parseLineChangeCounts(data)
        var counts = parsed.counts
        let binaryPaths = parsed.binaryPaths
        let untracked = files.filter { $0.status == .untracked }
        let untrackedCounts = (try? await UntrackedLineCountCache.shared.counts(for: untracked, in: repositoryURL)) ?? [:]
        counts.merge(untrackedCounts) { _, new in new }
        // Unchanged content (for example a mode-only change) has no numstat record.
        for file in files where counts[file.path] == nil && !binaryPaths.contains(file.path) && file.status != .untracked && file.status != .conflict {
            if !file.isBinary && !file.isImage { counts[file.path] = FileLineChangeCount(added: 0, removed: 0) }
        }
        return counts
    }

    func commitLineChangeCounts(in commit: String, in repositoryURL: URL) async throws -> [String: FileLineChangeCount] {
        let data = try await runGitRaw(arguments: [
            "show", "--numstat", "-z", "--find-renames", "--first-parent", "--format=",
            "--no-ext-diff", "--no-textconv", commit, "--"
        ], in: repositoryURL)
        return Self.parseLineChangeCounts(data).counts
    }

    nonisolated private static func parseLineChangeCounts(_ data: Data) -> (counts: [String: FileLineChangeCount], binaryPaths: Set<String>) {
        let records = data.split(separator: 0, omittingEmptySubsequences: false)
        var counts: [String: FileLineChangeCount] = [:]
        var binaryPaths = Set<String>()
        var index = 0
        while index < records.count {
            let fields = records[index].split(separator: 9, maxSplits: 2, omittingEmptySubsequences: false)
            index += 1
            guard fields.count == 3 else { continue }
            var path = String(decoding: fields[2], as: UTF8.self)
            if path.isEmpty {
                // Rename records contain an empty path, then old and new paths.
                guard index + 1 < records.count else { break }
                path = String(decoding: records[index + 1], as: UTF8.self)
                index += 2
            }
            guard let added = Int(String(decoding: fields[0], as: UTF8.self)),
                  let removed = Int(String(decoding: fields[1], as: UTF8.self)) else {
                binaryPaths.insert(path)
                continue
            }
            counts[path] = FileLineChangeCount(added: added, removed: removed)
        }
        return (counts, binaryPaths)
    }
}
