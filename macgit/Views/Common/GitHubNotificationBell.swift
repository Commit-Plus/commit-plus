// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitHubNotificationBell: View {
    @EnvironmentObject private var controller: GitHubNotificationController
    @EnvironmentObject private var appNotificationController: AppNotificationController
    @EnvironmentObject private var accountController: AccountSessionController
    @Environment(\.openWindow) private var openWindow
    @State private var isPresented = false
    @State private var presentationWindow: NSWindow?

    var body: some View {
        Button("Notifications", systemImage: unreadCount > 0 ? "bell.badge" : "bell") {
            if !isPresented { presentationWindow = NSApp.keyWindow }
            isPresented.toggle()
        }
        .labelStyle(.iconOnly)
        .help("Notifications · \(unreadCount) unread")
        .popover(isPresented: $isPresented) {
            GitHubNotificationPopover(
                controller: controller,
                appNotificationController: appNotificationController,
                onConnect: accountController.presentConnections,
                onAppNotification: openAppNotification
            ) { presentation in
                isPresented = false
                NotificationCenter.default.post(
                    name: .showReleaseNotes,
                    object: presentationWindow,
                    userInfo: ["presentation": presentation]
                )
            }
        }
    }

    private var unreadCount: Int {
        controller.unreadCount + appNotificationController.unreadCount
    }

    private func openAppNotification(_ notification: AppNotification) {
        isPresented = false
        appNotificationController.activate(notification)
        let repositoryURL = notification.repositoryURL.resolvingSymlinksInPath().standardizedFileURL
        if !RepositoryWindowContext.focusRepository(at: repositoryURL) {
            openWindow(id: "main", value: RepositoryWindowRequest.repository(
                repositoryURL,
                shouldFitVisibleScreen: true,
                showsPullRequests: notification.kind == .pullRequestCreated ? true : nil
            ))
        }
    }
}
