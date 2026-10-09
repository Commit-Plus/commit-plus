// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitHubNotificationBell: View {
    @EnvironmentObject private var controller: GitHubNotificationController
    @EnvironmentObject private var accountController: AccountSessionController
    @State private var isPresented = false
    @State private var presentationWindow: NSWindow?

    var body: some View {
        Button("GitHub Notifications", systemImage: controller.unreadCount > 0 ? "bell.badge" : "bell") {
            if !isPresented { presentationWindow = NSApp.keyWindow }
            isPresented.toggle()
        }
        .labelStyle(.iconOnly)
        .help("GitHub notifications · \(controller.unreadCount) unread in cache")
        .popover(isPresented: $isPresented) {
            GitHubNotificationPopover(controller: controller, onConnect: accountController.presentConnections) { presentation in
                isPresented = false
                NotificationCenter.default.post(
                    name: .showReleaseNotes,
                    object: presentationWindow,
                    userInfo: ["presentation": presentation]
                )
            }
        }
    }
}
