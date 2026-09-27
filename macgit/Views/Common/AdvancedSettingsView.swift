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

struct AdvancedSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject private var settings = AdvancedSettingsStore.shared
    @ObservedObject private var integrations = IntegrationSettingsStore.shared
    @ObservedObject private var recentRepositories = RecentRepositoriesStore.shared

    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var orphanedUndoReport: OrphanedUndoBackupReport?
    @State private var showingClearRecentConfirmation = false
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    title: "Verbose Git logging",
                    detail: "Record Git commands, duration, and success state. Credentials and command output are excluded.",
                    isOn: $settings.verboseGitLogging
                )

                HStack {
                    Button(
                        "Copy Diagnostic Report",
                        systemImage: "doc.on.doc",
                        action: copyDiagnosticReport
                    )
                    Button(
                        "Reveal Logs in Finder",
                        systemImage: "folder",
                        action: revealLogs
                    )
                }

                Button(
                    "Open Application Support",
                    systemImage: "externaldrive",
                    action: openApplicationSupport
                )
            } header: {
                Label("Diagnostics", systemImage: "stethoscope")
            } footer: {
                Text("Diagnostic reports contain app and runtime status only—never tokens, credentials, repository paths, or Git output.")
            }

            Section {
                Picker("History load size", selection: $settings.historyLoadSize) {
                    ForEach(HistoryLoadSize.allCases) { size in
                        Text("\(size.title) — \(size.detail)")
                            .tag(size)
                    }
                }

                Button(
                    "Clear Session Caches",
                    systemImage: "arrow.clockwise",
                    action: clearSessionCaches
                )
                .disabled(isWorking)
            } header: {
                Label("Performance & Cache", systemImage: "gauge.with.dots.needle.67percent")
            } footer: {
                Text("Balanced is recommended. Clearing session caches refreshes branch, history, and pull request data without changing repository files.")
            }

            Section {
                LabeledContent("Recent repositories") {
                    Text("\(recentRepositories.repositories.count)")
                        .foregroundStyle(.secondary)
                }

                Button(
                    "Clean Orphaned Undo Backups…",
                    systemImage: "trash",
                    action: inspectOrphanedUndoBackups
                )
                .disabled(isWorking || recentRepositories.repositories.isEmpty)

                Button(
                    "Clear Recent Repositories…",
                    systemImage: "clock.badge.xmark",
                    action: { showingClearRecentConfirmation = true }
                )
                .disabled(recentRepositories.repositories.isEmpty)

                Button(
                    "Reset Local App Settings…",
                    systemImage: "arrow.counterclockwise",
                    action: { showingResetConfirmation = true }
                )
            } header: {
                Label("Data & Maintenance", systemImage: "wrench.adjustable")
            } footer: {
                Text("Local reset covers Advanced, Integrations, search, and editor choices. Synced General and Appearance settings, accounts, Keychain items, Git runtime, and repositories are preserved.")
            }

            if isWorking || statusMessage != nil || errorMessage != nil {
                Section {
                    if isWorking {
                        ProgressView("Working…")
                            .controlSize(.small)
                    } else if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
        .confirmationDialog(
            "Remove Orphaned Undo Backups?",
            isPresented: Binding(
                get: { orphanedUndoReport != nil },
                set: { if !$0 { orphanedUndoReport = nil } }
            )
        ) {
            Button("Remove Backups", role: .destructive, action: removeOrphanedUndoBackups)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let report = orphanedUndoReport {
                Text("Remove \(report.count) backup folder\(report.count == 1 ? "" : "s") using \(formattedSize(report.byteCount))? Active undo operations are preserved.")
            }
        }
        .confirmationDialog(
            "Clear Recent Repositories?",
            isPresented: $showingClearRecentConfirmation
        ) {
            Button("Clear Recents", role: .destructive) {
                recentRepositories.removeAll()
                showStatus("Recent repositories cleared.")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only clears the Recent list. Repository folders are not deleted.")
        }
        .confirmationDialog(
            "Reset Local App Settings?",
            isPresented: $showingResetConfirmation
        ) {
            Button("Reset Settings", role: .destructive, action: resetLocalSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Advanced, Integrations, search, and editor choices will return to defaults. Accounts, credentials, synced settings, Git runtime, and repositories are preserved.")
        }
    }

    private func copyDiagnosticReport() {
        isWorking = true
        clearMessages()
        Task {
            let runtimeStatus = await GitRuntimeManager.shared.status()
            await MainActor.run {
                let report = AdvancedDiagnosticsService.report(
                    runtimeStatus: runtimeStatus,
                    cloudFeaturesAvailable: accountController.cloudFeaturesAvailable,
                    isSignedIn: accountController.account != nil,
                    settingsSyncStatus: accountController.settingsSyncDisplayText,
                    providerAccounts: providerAccountController.accounts,
                    integrationSettings: integrations
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
                isWorking = false
                showStatus("Diagnostic report copied.")
            }
        }
    }

    private func revealLogs() {
        do {
            try FileManager.default.createDirectory(
                at: GitCommandLogStore.logsDirectoryURL,
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: GitCommandLogStore.logFileURL.path) {
                FileManager.default.createFile(
                    atPath: GitCommandLogStore.logFileURL.path,
                    contents: nil
                )
            }
            NSWorkspace.shared.activateFileViewerSelecting([GitCommandLogStore.logFileURL])
            showStatus("Logs revealed in Finder.")
        } catch {
            showError(error)
        }
    }

    private func openApplicationSupport() {
        do {
            let url = AdvancedDiagnosticsService.applicationSupportDirectoryURL
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(url)
            showStatus("Application Support opened.")
        } catch {
            showError(error)
        }
    }

    private func clearSessionCaches() {
        isWorking = true
        clearMessages()
        Task {
            await GitStatusService.shared.clearSessionCaches()
            await PullRequestDiskCache.shared.remove()
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .advancedClearSessionCaches,
                    object: nil
                )
                isWorking = false
                showStatus("Session caches cleared.")
            }
        }
    }

    private func inspectOrphanedUndoBackups() {
        isWorking = true
        clearMessages()
        let repositoryURLs = recentRepositories.repositories.map(\.url)
        Task {
            let report = await AdvancedMaintenanceService.shared
                .orphanedUndoBackups(in: repositoryURLs)
            await MainActor.run {
                isWorking = false
                if report.count == 0 {
                    showStatus("No orphaned undo backups found.")
                } else {
                    orphanedUndoReport = report
                }
            }
        }
    }

    private func removeOrphanedUndoBackups() {
        guard let report = orphanedUndoReport else { return }
        orphanedUndoReport = nil
        isWorking = true
        clearMessages()
        Task {
            do {
                try await AdvancedMaintenanceService.shared.remove(report)
                await MainActor.run {
                    isWorking = false
                    showStatus("Removed \(report.count) orphaned undo backup\(report.count == 1 ? "" : "s").")
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    showError(error)
                }
            }
        }
    }

    private func resetLocalSettings() {
        appState.restoreLocalOnlyPreferences()
        integrations.restoreDefaults()
        settings.restoreDefaults()
        showStatus("Local app settings restored.")
    }

    private func formattedSize(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }

    private func clearMessages() {
        statusMessage = nil
        errorMessage = nil
    }

    private func showStatus(_ message: String) {
        errorMessage = nil
        statusMessage = message
    }

    private func showError(_ error: Error) {
        statusMessage = nil
        errorMessage = error.localizedDescription
    }
}
