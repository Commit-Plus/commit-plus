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
    private var syncAppCloudData: (() async -> Void)?
    private var awaitingTerminationReply = false
    private static let terminationSyncTimeout: Duration = .seconds(3)

    /// App-wide cloud data syncs when the last window closes (the app stays in the Dock) and
    /// before quitting. Repository-scoped data syncs when its own window closes.
    func installAppCloudSync(_ sync: @escaping () async -> Void) {
        syncAppCloudData = sync
    }

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if let syncAppCloudData { Task { await syncAppCloudData() } }
        return false
    }

    /// Quitting syncs app-wide data and every repository window that is still open, since
    /// those windows run `onDisappear` only after `applicationWillTerminate`, too late for
    /// async work. It waits at most `terminationSyncTimeout`.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !awaitingTerminationReply else { return .terminateNow }
        awaitingTerminationReply = true
        let syncAppCloudData = syncAppCloudData
        Task {
            async let appData: Void? = syncAppCloudData?()
            async let repositoryData: Void = RepositoryWindowCloudSyncRegistry.shared.uploadAll()
            _ = await (appData, repositoryData)
            replyToTermination(sender)
        }
        Task {
            try? await Task.sleep(for: Self.terminationSyncTimeout)
            replyToTermination(sender)
        }
        return .terminateLater
    }

    private func replyToTermination(_ sender: NSApplication) {
        guard awaitingTerminationReply else { return }
        awaitingTerminationReply = false
        sender.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityTelemetry?.stop()
        RepositoryActionAuditStore.terminateSession()
    }

    @IBAction func newWindowForTab(_ sender: Any?) {
        WindowScopedNotification.post(name: .newRepositoryTab)
    }
}
