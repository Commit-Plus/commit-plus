// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Foundation
import UserNotifications

extension Notification.Name {
    static let openPullRequestsFromUserNotification = Notification.Name(
        "macgit.openPullRequestsFromUserNotification"
    )
}

/// macOS system notifications, gated by `NotificationSettingsStore`.
enum SystemUserNotification {
    nonisolated static let repositoryPathKey = "repositoryPath"
    /// Present when the system notification mirrors an in-app `AppNotification`.
    nonisolated static let appNotificationIDKey = "appNotificationID"
    /// Lets an existing window absorb the notification click instead of SwiftUI
    /// spawning a new scene; the app delegate performs the actual navigation.
    nonisolated static let externalEventIdentifier = "macgit://pull-request-notification"

    @MainActor
    static func created(
        _ pullRequest: PullRequestSummary,
        repositoryURL: URL,
        warnings: [String]
    ) {
        guard NotificationSettingsStore.shared.pullRequestResultsEnabled else { return }
        let body = warnings.isEmpty
            ? "#\(pullRequest.number) \(pullRequest.title)"
            : "#\(pullRequest.number) was created. \(warnings.joined(separator: " "))"
        deliver(
            title: "Pull request created",
            body: body,
            repositoryURL: repositoryURL
        )
    }

    @MainActor
    static func creationFailed(message: String, repositoryURL: URL) {
        guard NotificationSettingsStore.shared.pullRequestResultsEnabled else { return }
        deliver(
            title: "Couldn’t create pull request",
            body: message,
            repositoryURL: repositoryURL
        )
    }

    /// Announces a newly recorded in-app notification. Pull request entries are skipped
    /// because `created` already reports them.
    @MainActor
    static func appNotificationAdded(_ notification: AppNotification) {
        guard NotificationSettingsStore.shared.appNotificationsEnabled else { return }
        switch notification.kind {
        case .fullyMergedBranches:
            let count = notification.branchNames.count
            deliver(
                title: notification.repositoryURL.lastPathComponent,
                body: count == 1
                    ? "1 fully merged branch can be deleted."
                    : "\(count) fully merged branches can be deleted.",
                repositoryURL: notification.repositoryURL,
                appNotificationID: notification.id
            )
        case .pullRequestCreated:
            break
        }
    }

    @MainActor
    private static func deliver(
        title: String,
        body: String,
        repositoryURL: URL,
        appNotificationID: String? = nil
    ) {
        if NotificationSettingsStore.shared.onlyWhenInactive, NSApp?.isActive == true { return }
        var userInfo: [String: String] = [repositoryPathKey: repositoryURL.standardizedFileURL.path]
        userInfo[appNotificationIDKey] = appNotificationID
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.userInfo = userInfo
                content.targetContentIdentifier = externalEventIdentifier
                try await center.add(UNNotificationRequest(
                    identifier: appNotificationID ?? UUID().uuidString,
                    content: content,
                    trigger: nil
                ))
            } catch {
                // Notifications are supplemental; results remain visible in the app.
            }
        }
    }
}
