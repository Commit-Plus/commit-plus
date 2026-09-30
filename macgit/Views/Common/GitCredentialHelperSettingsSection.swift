// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct GitCredentialHelperSettingsSection: View {
    @Bindable var viewModel: GitSettingsViewModel

    var body: some View {
        Section {
            Picker("Fallback Credential Helper", selection: $viewModel.credentialHelperMode) {
                Text("Commit+ connected accounts only")
                    .tag(GitCredentialHelperMode.commitPlusAccountsOnly)

                if viewModel.hasMultipleCredentialHelpers {
                    Text("Keep existing helper chain")
                        .tag(GitCredentialHelperMode.preserveExisting)
                }

                ForEach(viewModel.credentialHelperChoices, id: \.self) { helper in
                    Text(helper == "osxkeychain" ? "macOS Keychain — Recommended" : helper)
                        .tag(GitCredentialHelperMode.helper(helper))
                }
            }
            .disabled(viewModel.isBusy)

            if viewModel.credentialHelperMode == .preserveExisting {
                LabeledContent("Configured Helpers") {
                    VStack(alignment: .trailing) {
                        ForEach(Array(viewModel.settings.credentialHelperValues.enumerated()), id: \.offset) { _, helper in
                            if helper.isEmpty {
                                Label("Reset helper list", systemImage: "arrow.counterclockwise")
                                    .foregroundStyle(.secondary)
                            } else {
                                let availability = viewModel.availability(for: helper)
                                Label(helper, systemImage: availability.systemImage)
                                    .foregroundStyle(availability.isAvailable ? Color.green : Color.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            if let availability = viewModel.credentialHelperAvailability {
                LabeledContent("Active Runtime") {
                    Label(availability.title, systemImage: availability.systemImage)
                        .foregroundStyle(availability.isAvailable ? .green : .secondary)
                }
            }

            if viewModel.configuredCredentialsUseInsecureStore {
                Label(
                    "credential-store saves credentials unencrypted on disk. Choose macOS Keychain instead.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        } header: {
            Label("Credential Helper", systemImage: "key")
        } footer: {
            Text(
                "A matching Commit+ connected account is always used first. Otherwise HTTPS operations use this helper without falling back to a Terminal prompt. Changing this setting never deletes saved Keychain credentials."
            )
        }
    }
}
