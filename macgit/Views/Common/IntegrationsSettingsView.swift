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
import SwiftUI

struct IntegrationsSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var integrationSettings = IntegrationSettingsStore.shared

    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Picker(
                    "Preferred editor",
                    selection: $appState.preferredSearchFileApplicationBundleIdentifier
                ) {
                    Text("Ask Every Time").tag(nil as String?)
                    ForEach(editorApplications) { application in
                        Text(application.displayName)
                            .tag(Optional(application.bundleIdentifier))
                    }
                }

                LabeledContent("Detected editors") {
                    Text(detectedSummary(editorApplications))
                        .foregroundStyle(.secondary)
                }

                SettingsActionRow {
                    Button("Test Editor", systemImage: "play", action: testEditor)
                        .disabled(
                            appState.preferredSearchFileApplicationBundleIdentifier == nil
                                || isTesting
                        )
                }
            } header: {
                Label("External Editor", systemImage: "chevron.left.forwardslash.chevron.right")
            } footer: {
                Text("Used by the repository toolbar and when opening files from Search. Ask Every Time shows the installed-editor chooser.")
            }

            Section {
                Picker(
                    "Preferred terminal",
                    selection: $integrationSettings.preferredTerminalBundleIdentifier
                ) {
                    Text("Automatic").tag(nil as String?)
                    ForEach(terminalApplications) { application in
                        Text(application.displayName)
                            .tag(Optional(application.bundleIdentifier))
                    }
                }

                LabeledContent("Active terminal") {
                    Text(activeTerminalName)
                        .foregroundStyle(.secondary)
                }

                SettingsActionRow {
                    Button("Test Terminal", systemImage: "play", action: testTerminal)
                        .disabled(terminalApplications.isEmpty || isTesting)
                }
            } header: {
                Label("Terminal", systemImage: "terminal")
            } footer: {
                Text("Used by repository, worktree, submodule, and subtree Open in Terminal actions.")
            }

            Section {
                Picker(
                    "External diff tool",
                    selection: $integrationSettings.preferredDiffBundleIdentifier
                ) {
                    Text("Built-in Commit+").tag(nil as String?)
                    ForEach(diffApplications) { application in
                        Text(application.displayName)
                            .tag(Optional(application.bundleIdentifier))
                    }
                }

                Picker(
                    "External merge tool",
                    selection: $integrationSettings.preferredMergeBundleIdentifier
                ) {
                    Text("Built-in Commit+").tag(nil as String?)
                    ForEach(mergeApplications) { application in
                        Text(application.displayName)
                            .tag(Optional(application.bundleIdentifier))
                    }
                }

                SettingsActionRow {
                    Button("Test Diff Tool", action: testDiffTool)
                        .disabled(
                            integrationSettings.preferredDiffBundleIdentifier == nil
                                || isTesting
                        )
                    Button("Test Merge Tool", action: testMergeTool)
                        .disabled(
                            integrationSettings.preferredMergeBundleIdentifier == nil
                                || isTesting
                        )
                }
            } header: {
                Label("Diff & Merge", systemImage: "arrow.triangle.merge")
            } footer: {
                Text("Built-in Commit+ remains the safe fallback if a selected external application is removed.")
            }

            Section {
                SettingsActionRow {
                    Button(
                        "Refresh Installed Applications",
                        systemImage: "arrow.clockwise",
                        action: refreshApplications
                    )
                    .disabled(isTesting)
                }

                if isTesting {
                    ProgressView("Opening application…")
                        .controlSize(.small)
                } else if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Integrations")
        .onAppear(perform: refreshApplications)
    }

    private var editorApplications: [IntegrationApplication] {
        _ = integrationSettings.refreshID
        return IntegrationApplicationCatalog.availableApplications(for: .editor)
    }

    private var terminalApplications: [IntegrationApplication] {
        _ = integrationSettings.refreshID
        return IntegrationApplicationCatalog.availableApplications(for: .terminal)
    }

    private var diffApplications: [IntegrationApplication] {
        _ = integrationSettings.refreshID
        return IntegrationApplicationCatalog.availableApplications(for: .diff)
    }

    private var mergeApplications: [IntegrationApplication] {
        _ = integrationSettings.refreshID
        return IntegrationApplicationCatalog.availableApplications(for: .merge)
    }

    private var activeTerminalName: String {
        integrationSettings.selectedApplication(for: .terminal)?.displayName
            ?? "No supported terminal found"
    }

    private func detectedSummary(_ applications: [IntegrationApplication]) -> String {
        applications.isEmpty
            ? "No supported applications found"
            : "\(applications.count) installed"
    }

    private func refreshApplications() {
        integrationSettings.refreshApplications()
        validateEditorSelection()
        statusMessage = "Installed applications refreshed."
        errorMessage = nil
    }

    private func validateEditorSelection() {
        guard let selectedBundleIdentifier =
                appState.preferredSearchFileApplicationBundleIdentifier else {
            return
        }
        if !editorApplications.contains(where: {
            $0.bundleIdentifier == selectedBundleIdentifier
        }) {
            appState.preferredSearchFileApplicationBundleIdentifier = nil
        }
    }

    private func testEditor() {
        guard let bundleIdentifier =
                appState.preferredSearchFileApplicationBundleIdentifier,
              let editor = editorApplications.first(where: {
                  $0.bundleIdentifier == bundleIdentifier
              }) else {
            return
        }
        test(application: editor)
    }

    private func testTerminal() {
        test(role: .terminal)
    }

    private func testDiffTool() {
        test(role: .diff)
    }

    private func testMergeTool() {
        test(role: .merge)
    }

    private func test(application: IntegrationApplication) {
        performTest(application.displayName) {
            try await IntegrationApplicationLauncher.launch(application)
        }
    }

    private func test(role: IntegrationRole) {
        let name = integrationSettings.selectedApplication(for: role)?.displayName
            ?? role.rawValue.capitalized
        performTest(name) {
            try await integrationSettings.test(role: role)
        }
    }

    private func performTest(
        _ applicationName: String,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        isTesting = true
        statusMessage = nil
        errorMessage = nil
        Task { @MainActor in
            defer { isTesting = false }
            do {
                try await operation()
                statusMessage = "\(applicationName) opened successfully."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
