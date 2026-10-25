// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

/// Device-local preferences for macOS system notifications. Not cloud-synced: whether a Mac
/// shows banners is a per-device choice, like the system notification permission itself.
@MainActor
final class NotificationSettingsStore: ObservableObject {
    static let shared = NotificationSettingsStore()

    private enum Key {
        static let pullRequestResults = "dev.thanhtran.macgit.notifications.pullRequestResults"
        static let appNotifications = "dev.thanhtran.macgit.notifications.appNotifications"
        static let onlyWhenInactive = "dev.thanhtran.macgit.notifications.onlyWhenInactive"
    }

    private let defaults: UserDefaults

    /// Pull request creation succeeded or failed.
    @Published var pullRequestResultsEnabled: Bool {
        didSet { defaults.set(pullRequestResultsEnabled, forKey: Key.pullRequestResults) }
    }

    /// A new in-app notification (for example, fully merged branches ready to delete).
    @Published var appNotificationsEnabled: Bool {
        didSet { defaults.set(appNotificationsEnabled, forKey: Key.appNotifications) }
    }

    /// Skip system notifications while Commit+ is frontmost, since the result is already on screen.
    @Published var onlyWhenInactive: Bool {
        didSet { defaults.set(onlyWhenInactive, forKey: Key.onlyWhenInactive) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pullRequestResultsEnabled = defaults.object(forKey: Key.pullRequestResults) as? Bool ?? true
        appNotificationsEnabled = defaults.object(forKey: Key.appNotifications) as? Bool ?? true
        onlyWhenInactive = defaults.object(forKey: Key.onlyWhenInactive) as? Bool ?? false
    }
}
