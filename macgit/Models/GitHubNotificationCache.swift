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

    mutating func merge(with values: [GitHubNotification]) {
        var merged: [String: GitHubNotification] = [:]
        for item in notifications + values {
            if let existing = merged[item.id] {
                guard item.updatedAt >= existing.updatedAt else { continue }
                var next = item
                // The same server version must not undo a local Done action.
                // New activity on the thread returns it to the inbox.
                if item.updatedAt == existing.updatedAt { next.doneAt = existing.doneAt }
                merged[item.id] = next
            } else {
                merged[item.id] = item
            }
        }
        notifications = Array(merged.values.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
            return $0.updatedAt > $1.updatedAt
        }.prefix(50))
        let retainedIDs = Set(notifications.map(\.id))
        pendingReads = pendingReads?.filter { retainedIDs.contains($0.key) }
    }
}
