// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import UserNotifications

extension Notification.Name {
    static let openPullRequestsFromUserNotification = Notification.Name(
        "macgit.openPullRequestsFromUserNotification"
    )
}

enum PullRequestUserNotification {
    nonisolated static let repositoryPathKey = "repositoryPath"
    /// Lets an existing window absorb the notification click instead of SwiftUI
    /// spawning a new scene; the app delegate performs the actual navigation.
    nonisolated static let externalEventIdentifier = "macgit://pull-request-notification"

    @MainActor
    static func created(
        _ pullRequest: PullRequestSummary,
        repositoryURL: URL,
        warnings: [String]
    ) {
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
        deliver(
            title: "Couldn’t create pull request",
            body: message,
            repositoryURL: repositoryURL
        )
    }

    @MainActor
    private static func deliver(title: String, body: String, repositoryURL: URL) {
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.userInfo = [repositoryPathKey: repositoryURL.standardizedFileURL.path]
                content.targetContentIdentifier = externalEventIdentifier
                try await center.add(UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                ))
            } catch {
                // Notifications are supplemental; creation results remain visible in the app.
            }
        }
    }
}
