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

struct GitSettingsView: View {
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @State private var viewModel = GitSettingsViewModel()
    @State private var providerPresentation = GitProviderSettingsPresentation()
    @FocusState private var focusedField: Field?

    /// Text fields save when editing ends, since Git rejects partial values such as an incomplete email.
    private enum Field: Hashable {
        case userName, userEmail, defaultBranchName, excludesFilePath

        var keyPath: WritableKeyPath<GlobalGitSettings, String> {
            switch self {
            case .userName: \.userName
            case .userEmail: \.userEmail
            case .defaultBranchName: \.defaultBranchName
            case .excludesFilePath: \.excludesFilePath
            }
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            GitRuntimeSettingsSection(viewModel: viewModel)
            GitLFSRuntimeSection()
            GitProviderSettingsSection(
                accountController: accountController,
                providerAccountController: providerAccountController,
                presentation: $providerPresentation
            )
            GitCredentialHelperSettingsSection(viewModel: viewModel)

            Section {
                TextField("Full Name", text: $viewModel.settings.userName)
                    .focused($focusedField, equals: .userName)
                    .onSubmit { save(committing: \.userName) }
                TextField("Email Address", text: $viewModel.settings.userEmail)
                    .focused($focusedField, equals: .userEmail)
                    .onSubmit { save(committing: \.userEmail) }
            } header: {
                Label("Global Author", systemImage: "person.text.rectangle")
            } footer: {
                Text("Repositories with a local author override will continue to use their repository-specific identity.")
            }

            Section {
                TextField("Default Branch Name", text: $viewModel.settings.defaultBranchName)
                    .focused($focusedField, equals: .defaultBranchName)
                    .onSubmit { save(committing: \.defaultBranchName) }

                SettingsToggleRow(
                    title: "Prune deleted remote branches",
                    detail: "Run future fetches with the global fetch.prune behavior enabled.",
                    isOn: $viewModel.settings.pruneOnFetch
                )

                SettingsToggleRow(
                    title: "Set upstream on first push",
                    detail: "Automatically configure tracking when a new local branch is pushed for the first time.",
                    isOn: $viewModel.settings.autoSetupRemote
                )
            } header: {
                Label("Repository Defaults", systemImage: "arrow.triangle.branch")
            }

            Section {
                TextField("Ignore File Path", text: $viewModel.settings.excludesFilePath)
                    .focused($focusedField, equals: .excludesFilePath)
                    .onSubmit { save(committing: \.excludesFilePath) }

                SettingsActionRow {
                    Button("Choose…") {
                        viewModel.chooseGlobalIgnoreFile()
                        save(committing: \.excludesFilePath)
                    }
                    Button("Use Default") {
                        viewModel.useDefaultGlobalIgnoreFile()
                        save(committing: \.excludesFilePath)
                    }
                    Button("Open Ignore File…", action: viewModel.openGlobalIgnoreFile)
                }
            } header: {
                Label("Global Ignore File", systemImage: "doc.badge.ellipsis")
            } footer: {
                Text("Patterns in this file are ignored across all repositories on this Mac.")
            }

            Section {
            } footer: {
                HStack {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving…")
                            .foregroundStyle(.secondary)
                    } else if let saveErrorMessage = viewModel.saveErrorMessage {
                        Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else if let statusMessage = viewModel.statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Spacer(minLength: 0)

                    Button("Open Global Git Config…", action: viewModel.openGlobalGitConfig)
                }
                .font(.body)
                .foregroundStyle(.primary)
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Git")
        .disabled(viewModel.isLoading)
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading Git settings…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .gitProviderSettingsPresentations(
            accountController: accountController,
            providerAccountController: providerAccountController,
            presentation: $providerPresentation
        )
        .task {
            await viewModel.load()
        }
        .onChange(of: focusedField) { previous, current in
            viewModel.editingTextField = current?.keyPath
            if previous != nil { save() }
        }
        .onChange(of: viewModel.settings.pruneOnFetch) { save() }
        .onChange(of: viewModel.settings.autoSetupRemote) { save() }
        .onChange(of: viewModel.credentialHelperMode) { save() }
        .onDisappear {
            viewModel.editingTextField = nil
            save()
        }
        .alert("Git Settings Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog(
            "Replace existing credential helpers?",
            isPresented: $viewModel.showingCredentialHelperReplacementConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Helpers", role: .destructive, action: replaceCredentialHelpers)
            Button("Cancel", role: .cancel, action: viewModel.cancelCredentialHelperReplacement)
        } message: {
            Text(
                "This global Git configuration contains multiple credential helpers. Commit+ will replace the helper chain, but it will not delete credentials stored by those helpers."
            )
        }
    }

    private func save(committing field: WritableKeyPath<GlobalGitSettings, String>? = nil) {
        viewModel.requestSave(committing: field)
    }

    private func replaceCredentialHelpers() {
        viewModel.requestSave(allowCredentialHelperReplacement: true)
    }
}
