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
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    title: "Fill screen when opening repositories",
                    detail: "Expand newly opened repository windows to the available screen area. When off, they open at the same size as Welcome.",
                    isOn: $appState.fitRepositoryWindowsToScreen
                )
            } header: {
                Label("Windows", systemImage: "macwindow")
            }

            Section {
                SettingsToggleRow(
                    title: "Show Git Flow",
                    detail: "Include Git Flow workflow actions as a dedicated repository sidebar section.",
                    isOn: $appState.showGitFlow
                )

                SettingsToggleRow(
                    title: "Show submodules",
                    detail: "Include Git submodules as a dedicated section in the repository sidebar.",
                    isOn: $appState.showSubmodules
                )

                SettingsToggleRow(
                    title: "Show subtrees",
                    detail: "Include configured Git subtrees in the repository sidebar.",
                    isOn: $appState.showSubtrees
                )
            } header: {
                Label("Repository Sidebar", systemImage: "sidebar.left")
            }

            Section {
                SettingsToggleRow(
                    title: "Include remote branches",
                    detail: "Make remote branches available when filtering commit history.",
                    isOn: $appState.historyIncludeRemotes
                )
            } header: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            Section {
                SettingsToggleRow(
                    title: "Auto fetch",
                    detail: "Periodically fetch repositories that use the global setting.",
                    isOn: $appState.autoFetchEnabled
                )

                SettingsToggleRow(
                    title: "Refresh when app becomes active",
                    detail: "Refresh repositories that use the global setting when Commit+ becomes active.",
                    isOn: $appState.refreshOnAppActive
                )
            } header: {
                Label("Pull & Fetch", systemImage: "arrow.triangle.2.circlepath")
            }

            CommandLineSettingsSection()

            Section {
                Button("Restore General Defaults…", action: showResetConfirmation)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .confirmationDialog(
            "Restore General Defaults?",
            isPresented: $showingResetConfirmation
        ) {
            Button("Restore Defaults", role: .destructive, action: restoreDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Window, Sidebar, History, and Pull & Fetch preferences on this page will be reset.")
        }
    }

    private func showResetConfirmation() {
        showingResetConfirmation = true
    }

    private func restoreDefaults() {
        appState.fitRepositoryWindowsToScreen = false
        appState.showGitFlow = true
        appState.showSubmodules = false
        appState.showSubtrees = false
        appState.historyIncludeRemotes = false
        appState.autoFetchEnabled = false
        appState.refreshOnAppActive = true
    }
}
