// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Identifies the inputs a working-copy diff is built from, so a cached diff is
/// reused only while neither the git objects nor the file on disk changed.
struct FileStatusDiffFingerprint: Equatable {
    /// HEAD/index (or conflict stage) object IDs from porcelain v2 status.
    let objectIDs: String?
    let worktree: WorktreeStamp?

    /// The same stat data git uses to decide whether a worktree file may have changed.
    struct WorktreeStamp: Equatable {
        let size: UInt64?
        let modificationDate: Date?
        let fileNumber: UInt64?
    }

    /// Returns nil when the diff cannot be validated cheaply and should not be cached.
    init?(key: FileStatusSelectionKey, objectIDs: [String: String], repositoryURL: URL) {
        let fileObjectIDs = objectIDs[key.path]
        // Untracked files and untracked rename destinations are diffed from disk only;
        // every other diff reads git objects.
        guard fileObjectIDs != nil || key.isDiffedFromDisk else { return nil }
        self.objectIDs = fileObjectIDs

        // Staged and deleted diffs come from HEAD/index alone; the rest also read the worktree file.
        let readsWorktree = key.status == .conflict || (!key.isStaged && key.status != .deleted)
        if readsWorktree {
            let path = repositoryURL.appendingPathComponent(key.path).path
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            worktree = WorktreeStamp(
                size: (attributes?[.size] as? NSNumber)?.uint64Value,
                modificationDate: attributes?[.modificationDate] as? Date,
                fileNumber: (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
            )
        } else {
            worktree = nil
        }
    }
}

/// Keeps recently viewed working-copy diffs so switching between files does not
/// rerun git or show a loading state when nothing changed.
@MainActor
final class FileStatusDiffCache {
    /// Diffs larger than this are not cached, so a few huge files cannot pin a lot of memory.
    private static let maxCachedDiffLines = 20_000

    private struct Key: Hashable {
        let repositoryURL: URL
        let selection: FileStatusSelectionKey
    }

    private struct Entry {
        let fingerprint: FileStatusDiffFingerprint
        let hunks: [DiffHunk]
    }

    private var entries = BoundedMemoryCache<Key, Entry>(capacity: 30)

    func hunks(
        for selection: FileStatusSelectionKey,
        in repositoryURL: URL,
        matching fingerprint: FileStatusDiffFingerprint?
    ) -> [DiffHunk]? {
        guard let fingerprint else { return nil }
        let key = Key(repositoryURL: repositoryURL, selection: selection)
        guard let entry = entries.value(for: key) else { return nil }
        guard entry.fingerprint == fingerprint else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.hunks
    }

    func store(
        _ hunks: [DiffHunk],
        for selection: FileStatusSelectionKey,
        in repositoryURL: URL,
        fingerprint: FileStatusDiffFingerprint?
    ) {
        let key = Key(repositoryURL: repositoryURL, selection: selection)
        guard let fingerprint,
              hunks.reduce(0, { $0 + $1.lines.count }) <= Self.maxCachedDiffLines else {
            entries.removeValue(forKey: key)
            return
        }
        entries.insert(Entry(fingerprint: fingerprint, hunks: hunks), for: key)
    }
}
