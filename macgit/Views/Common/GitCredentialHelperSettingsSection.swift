// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct GitCredentialHelperSettingsSection: View {
    @Bindable var viewModel: GitSettingsViewModel
    @AppStorage(GitStatusService.credentialHelperFallbackKey) private var fallsBackWhenAccountIsRejected = true

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

            Toggle(isOn: $fallsBackWhenAccountIsRejected) {
                Text("Fall back to Git credential helpers")
                Text("Retry with your Git credential helpers when a connected account is rejected, for example when it cannot access a private repository.")
            }

            if fallsBackWhenAccountIsRejected {
                Label(
                    "Fallback uses whatever account your Git helpers are signed in to, such as the global GitHub CLI (gh) login. Pushes and other remote actions may then run as a different username than your Commit+ connected account.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

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
