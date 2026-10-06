// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct GitHubNotificationCache: Codable {
    var notifications: [GitHubNotification] = []
    var lastModified: String?
    var refreshedAt: Date?
    var nextFetchAt: Date?
    var retryAt: Date?
    var pendingReads: [String: Date]?

    static func key(for account: GitProviderAccount) -> String {
        // Include the local owner as well, isolating Commit+ sessions.
        GitProviderTokenVaultKey.key(for: account)
    }

    mutating func replace(with values: [GitHubNotification]) {
        var seen = Set<String>()
        notifications = Array(values.sorted { $0.updatedAt > $1.updatedAt }
            .filter { seen.insert($0.id).inserted }.prefix(50))
    }
}
