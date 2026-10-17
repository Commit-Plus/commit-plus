// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct RepositoryCatalogSnapshot: Codable, Equatable {
    struct Repository: Codable, Equatable, Identifiable {
        var id = UUID()
        var path: String
        var name: String
        var provider = "code-branch"
        var bookmarkKey: String?
        var lastOpened: Date?
        var lastSeen: Date?
    }

    struct Root: Codable, Equatable, Identifiable {
        var id = UUID()
        var path: String
        var addedAt = Date.now
        var scannedAt: Date?
        var error: String?
    }

    struct Membership: Codable, Equatable {
        var rootID: UUID
        var repositoryID: UUID
    }

    var repositories: [Repository] = []
    var roots: [Root] = []
    var memberships: [Membership] = []

    static func path(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    mutating func ensureRepository(_ url: URL) -> Int {
        let path = Self.path(url)
        if let index = repositories.firstIndex(where: { $0.path == path }) { return index }
        repositories.append(Repository(path: path, name: url.lastPathComponent))
        return repositories.count - 1
    }
}
