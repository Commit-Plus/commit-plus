// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @ObservedObject private var store = NotificationSettingsStore.shared
    @State private var authorizationStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    title: "Pull request results",
                    detail: "Notify when a pull request is created or could not be created.",
                    systemImage: "arrow.triangle.pull",
                    isOn: $store.pullRequestResultsEnabled
                )

                SettingsToggleRow(
                    title: "New app notifications",
                    detail: "Notify when Commit+ adds a notification, such as fully merged branches that can be deleted.",
                    systemImage: "bell.badge",
                    isOn: $store.appNotificationsEnabled
                )
            } header: {
                Label("Notify Me About", systemImage: "bell")
            }

            Section {
                SettingsToggleRow(
                    title: "Only when Commit+ is in the background",
                    detail: "Skip system notifications while Commit+ is the active app, since the result is already on screen.",
                    isOn: $store.onlyWhenInactive
                )
                .disabled(!store.pullRequestResultsEnabled && !store.appNotificationsEnabled)
            } header: {
                Label("Delivery", systemImage: "macwindow.badge.plus")
            } footer: {
                permissionFooter
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .task { await refreshAuthorizationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAuthorizationStatus() }
        }
    }

    @ViewBuilder
    private var permissionFooter: some View {
        if authorizationStatus == .denied {
            HStack {
                Text("Notifications for Commit+ are turned off in System Settings.")
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Button("Open System Settings", action: openSystemNotificationSettings)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .buttonStyle(.bordered)
            }
        } else {
            Text("Notifications always appear in the Commit+ notification menu. These settings only control macOS banners.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openSystemNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
