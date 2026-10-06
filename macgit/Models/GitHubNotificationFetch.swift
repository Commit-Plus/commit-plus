// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct GitHubNotificationFetch {
    /// nil means 304: retain the existing list.
    var notifications: [GitHubNotification]?
    var lastModified: String?
    var pollInterval: TimeInterval
}
