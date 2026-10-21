//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import AppKit
import UserNotifications

extension Notification.Name {
    static let newRepositoryTab = Notification.Name("macgit.newRepositoryTab")
}

@MainActor
final class MacgitApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var openRepositoryWindow: ((RepositoryWindowRequest) -> Void)?
    private var pendingRepositoryRequests: [RepositoryWindowRequest] = []

    func installRepositoryWindowOpener(_ opener: @escaping (RepositoryWindowRequest) -> Void) {
        openRepositoryWindow = opener
        let requests = pendingRepositoryRequests
        pendingRepositoryRequests.removeAll()
        requests.forEach(opener)
    }

    private var activityTelemetry: AppActivityTelemetryController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        activityTelemetry = AppTelemetry.makeActivityController()
        activityTelemetry?.start()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let repositoryPath = response.notification.request.content.userInfo[
                PullRequestUserNotification.repositoryPathKey
              ] as? String else { return }
        await MainActor.run {
            NSApp.activate()
            let repositoryURL = URL(fileURLWithPath: repositoryPath).standardizedFileURL
            if !OpenRepositoryRegistry.shared.isOpen(repositoryURL) {
                let request = RepositoryWindowRequest.repository(
                    repositoryURL,
                    shouldFitVisibleScreen: AppState.shared.fitRepositoryWindowsToScreen,
                    showsPullRequests: true
                )
                if let openRepositoryWindow = self.openRepositoryWindow {
                    openRepositoryWindow(request)
                } else {
                    self.pendingRepositoryRequests.append(request)
                }
                return
            }
            NotificationCenter.default.post(
                name: .openPullRequestsFromUserNotification,
                object: nil,
                userInfo: [PullRequestUserNotification.repositoryPathKey: repositoryPath]
            )
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activityTelemetry?.recordActivity(isActive: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityTelemetry?.stop()
        RepositoryActionAuditStore.terminateSession()
    }

    @IBAction func newWindowForTab(_ sender: Any?) {
        WindowScopedNotification.post(name: .newRepositoryTab)
    }
}
