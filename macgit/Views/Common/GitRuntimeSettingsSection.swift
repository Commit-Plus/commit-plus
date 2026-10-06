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

struct GitRuntimeSettingsSection: View {
    @Bindable var viewModel: GitSettingsViewModel

    var body: some View {
        Section {
            Picker("Git Runtime", selection: $viewModel.selectedRuntimePreference) {
                ForEach(GitRuntimePreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isBusy)
            .onChange(of: viewModel.selectedRuntimePreference) { _, preference in
                Task { await viewModel.selectRuntimePreference(preference) }
            }

            if viewModel.selectedRuntimePreference == .automatic {
                Text("Uses System Git when available, otherwise Embedded Git.")
                    .foregroundStyle(.secondary)
            }

            LabeledContent {
                VStack(alignment: .trailing) {
                    GitRuntimeInstallationLabel(runtime: viewModel.visibleRuntime)

                    if viewModel.shouldOfferEmbeddedDownload {
                        if viewModel.isDownloadingEmbeddedGit {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Downloading…")
                            }
                        } else {
                            Button(
                                "Download \(viewModel.embeddedVersion) (\(viewModel.embeddedDownloadSizeDescription))",
                                systemImage: "arrow.down.circle",
                                action: downloadEmbeddedGit
                            )
                        }
                    }
                }
            } label: {
                Label(
                    viewModel.visibleRuntimeTitle,
                    systemImage: viewModel.visibleRuntimeSystemImage
                )
            }

            SettingsActionRow {
                Button(
                    "Refresh Git Information",
                    systemImage: "arrow.clockwise",
                    action: refresh
                )
                .disabled(viewModel.isBusy)
            }
        } header: {
            Label("Git Installation", systemImage: "terminal")
        } footer: {
            Text("The runtime choice and Embedded Git installation are stored only on this Mac.")
        }
    }

    private func downloadEmbeddedGit() {
        Task { await viewModel.downloadEmbeddedGit() }
    }

    private func refresh() {
        Task { await viewModel.load() }
    }
}
