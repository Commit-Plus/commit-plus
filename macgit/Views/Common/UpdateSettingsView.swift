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

struct UpdateSettingsView: View {
    @ObservedObject var updateController: AppUpdateController

    var body: some View {
        Form {
            Section {
                LabeledContent("Current version") {
                    Text(currentVersionLabel)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Latest version") {
                    latestVersionContent
                }
            } header: {
                Label("Version", systemImage: "info.circle")
            }

            Section {
                SettingsActionRow {
                    updateAction
                }
            } header: {
                Label("Software Update", systemImage: "arrow.triangle.2.circlepath")
            } footer: {
                Text(statusMessage)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Update")
    }

    @ViewBuilder
    private var latestVersionContent: some View {
        if updateController.state == .checking {
            ProgressView()
                .controlSize(.small)
        } else {
            Text(updateController.latestVersion ?? "Not checked yet")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        switch updateController.state {
        case .available:
            Button(
                updateButtonTitle,
                systemImage: "arrow.down.to.line",
                action: updateController.openUpdateWindow
            )
            .buttonStyle(.borderedProminent)
        case .downloading:
            ProgressView("Downloading update…")
                .controlSize(.small)
        case .idle, .checking:
            Button(
                "Check for Updates",
                systemImage: "arrow.clockwise",
                action: updateController.refreshLatestVersion
            )
            .disabled(updateController.state == .checking)
        }
    }

    private var currentVersionLabel: String {
        guard let currentBuild = updateController.currentBuild,
              !currentBuild.isEmpty else {
            return updateController.currentVersion
        }
        return "\(updateController.currentVersion) (\(currentBuild))"
    }

    private var updateButtonTitle: String {
        guard let latestVersion = updateController.latestVersion else {
            return "Install Update…"
        }
        return "Install Version \(latestVersion)…"
    }

    private var statusMessage: String {
        switch updateController.state {
        case .idle:
            if let error = updateController.latestVersionCheckError {
                return "Couldn’t check for updates: \(error)"
            }
            if updateController.latestVersion == nil {
                return "Check the update feed for the latest available version."
            }
            return "No newer compatible update is available."
        case .checking:
            return "Checking the update feed…"
        case .available:
            return "A newer version of Commit+ is available."
        case .downloading:
            return "The update is downloading and will be ready to install shortly."
        }
    }
}
