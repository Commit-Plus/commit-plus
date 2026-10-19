// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct AppNotification: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case fullyMergedBranches
    }

    let id: String
    let kind: Kind
    let repositoryPath: String
    let branchNames: [String]
    let createdAt: Date
    var readAt: Date?

    var repositoryURL: URL {
        URL(fileURLWithPath: repositoryPath, isDirectory: true)
    }
}
