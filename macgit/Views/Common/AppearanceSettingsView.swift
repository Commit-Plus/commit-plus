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

struct AppearanceSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appState.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.title, systemImage: appearance.systemImage)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Theme", systemImage: "circle.lefthalf.filled")
            } footer: {
                Text("System follows the current macOS appearance automatically.")
            }

            Section {
                Picker("Text size", selection: $appState.textSize) {
                    ForEach(AppTextSize.allCases) { textSize in
                        Text(textSize.title)
                            .tag(textSize)
                    }
                }
                .pickerStyle(.segmented)

                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.body.scaled(by: appState.textSize.scale))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } header: {
                Label("Text Size", systemImage: "textformat.size")
            } footer: {
                Text("Larger text is useful on high-resolution and large displays. This setting applies only to this Mac.")
            }

            Section {
                SettingsToggleRow(
                    title: "Show button text",
                    detail: "Display labels alongside icons in the main repository toolbar.",
                    isOn: $appState.showToolbarButtonText
                )
            } header: {
                Label("Toolbar", systemImage: "macwindow")
            }

            Section {
                SettingsToggleRow(
                    title: "Branch",
                    detail: "Show the Branch action in the repository header.",
                    systemImage: "arrow.triangle.branch",
                    isOn: $appState.showHeaderBranchButton
                )

                SettingsToggleRow(
                    title: "Merge",
                    detail: "Show the Merge action in the repository header.",
                    systemImage: "arrow.triangle.merge",
                    isOn: $appState.showHeaderMergeButton
                )

                SettingsToggleRow(
                    title: "Stash",
                    detail: "Show the Stash action in the repository header.",
                    systemImage: "archivebox",
                    isOn: $appState.showHeaderStashButton
                )

            } header: {
                Label("Header Shortcuts", systemImage: "rectangle.topthird.inset.filled")
            } footer: {
                Text("Manage right-side repository shortcuts from the toolbar panel.")
            }

            Section {
                SettingsActionRow {
                    Button("Restore Appearance Defaults…", action: showResetConfirmation)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
        .confirmationDialog(
            "Restore Appearance Defaults?",
            isPresented: $showingResetConfirmation
        ) {
            Button("Restore Defaults", role: .destructive, action: restoreDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Theme, text size, toolbar, and header preferences on this page will be reset.")
        }
    }

    private func showResetConfirmation() {
        showingResetConfirmation = true
    }

    private func restoreDefaults() {
        appState.appearance = .system
        appState.textSize = .default
        appState.showToolbarButtonText = true
        appState.showHeaderBranchButton = true
        appState.showHeaderMergeButton = true
        appState.showHeaderStashButton = true
    }
}
