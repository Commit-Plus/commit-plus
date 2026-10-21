// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct ImageComparisonRequest: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case revision(String, String)
        case index(String)
        case disk(String)
    }
    let before: Source?
    let after: Source?

    static func working(_ file: StatusFile, staged: Bool) -> Self {
        Self(before: file.status == .untracked || file.status == .added ? nil :
                (staged ? .revision("HEAD", file.originalPath ?? file.path) :
                    .index(file.path)),
             after: file.status == .deleted ? nil : (staged ? .index(file.path) : .disk(file.path)))
    }

    static func commit(path: String, oldPath: String?, status: CommitFileStatus?, ref: String) -> Self {
        Self(before: status == .added ? nil : .revision("\(ref)^1", oldPath ?? path),
             after: status == .deleted ? nil : .revision(ref, path))
    }
}
