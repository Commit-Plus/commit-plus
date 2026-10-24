// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The Jira section of Settings → Integrations.
struct JiraIntegrationSection: View {
    @ObservedObject var controller: JiraConnectionController
    let onSignIn: () -> Void
    @State private var sheetMode: JiraConnectSheet.Mode?
    @State private var isConfirmingRemoval = false

    var body: some View {
        Section {
            if !controller.isSignedIn {
                LabeledContent("Status") {
                    Text("Sign in to Commit+ to connect Jira")
                        .foregroundStyle(.secondary)
                }
                actions {
                    Button("Sign In", action: onSignIn)
                }
            } else if let connection = controller.connection {
                LabeledContent("Site") {
                    Text(connection.siteHost)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Account") {
                    Text("\(connection.displayName) · \(connection.email)")
                        .foregroundStyle(.secondary)
                }
                if connection.needsReconnect {
                    Label("Jira no longer accepts the saved API token. Reconnect to keep using Jira.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let errorMessage = controller.errorMessage, sheetMode == nil {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                actions {
                    if controller.isWorking { ProgressView().controlSize(.small) }
                    Button("Reconnect…") { sheetMode = .reconnect }
                        .disabled(controller.isWorking)
                    Button("Remove…", role: .destructive) { isConfirmingRemoval = true }
                        .disabled(controller.isWorking)
                }
            } else {
                LabeledContent("Status") {
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                }
                actions {
                    Button("Connect Jira…") { sheetMode = .connect }
                        .disabled(!controller.hasLoaded || controller.isWorking)
                }
            }
        } header: {
            Label {
                Text("Jira")
            } icon: {
                Image("jira")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
        } footer: {
            Text("Connect a Jira Cloud site with an Atlassian API token to see your sprint issues in the Jira workspace screen. The token is stored only in this Mac's Keychain.")
        }
    }

    /// Sheets and alerts hang off the action row so they attach to a single view inside the form.
    private func actions<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        SettingsActionRow(content: content)
            .replacingSheet(item: $sheetMode) { mode in
                JiraConnectSheet(controller: controller, mode: mode)
            }
            .alert("Remove Jira Connection?", isPresented: $isConfirmingRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    Task { await controller.remove() }
                }
            } message: {
                Text("This removes the Jira site and its API token from this Mac. The token is not revoked at Atlassian; revoke it from your Atlassian account if you no longer need it.")
            }
    }
}

struct JiraConnectSheet: View {
    enum Mode: String, Identifiable {
        case connect
        case reconnect

        var id: String { rawValue }
    }

    static let apiTokenPageURL = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var controller: JiraConnectionController
    let mode: Mode
    @State private var site = ""
    @State private var email = ""
    @State private var token = ""

    private var canSubmit: Bool {
        let hasToken = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch mode {
        case .connect:
            return hasToken
                && !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .reconnect:
            return hasToken
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    if mode == .connect {
                        TextField("Site", text: $site, prompt: Text("your-site.atlassian.net"))
                        TextField("Email", text: $email, prompt: Text("Atlassian account email"))
                            .textContentType(.username)
                    } else if let connection = controller.connection {
                        LabeledContent("Site", value: connection.siteHost)
                        LabeledContent("Email", value: connection.email)
                    }
                    SecureField("API Token", text: $token)
                } header: {
                    Text(mode == .connect ? "Connect Jira Cloud" : "Reconnect Jira")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Only Jira Cloud sites are supported. Create a Jira API token in your Atlassian account; a Bitbucket API token does not include Jira access. For a scoped token, include the read:jira-work and read:jira-user scopes.")
                        Button("Create an API token…") { openURL(Self.apiTokenPageURL) }
                            .buttonStyle(.link)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = controller.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if controller.isWorking {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking with Jira…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .connect ? "Connect" : "Reconnect", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || controller.isWorking)
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear { controller.errorMessage = nil }
        .onDisappear { if !controller.isWorking { controller.errorMessage = nil } }
    }

    private func submit() {
        Task {
            let succeeded = switch mode {
            case .connect:
                await controller.connect(site: site, email: email, token: token)
            case .reconnect:
                await controller.reconnect(token: token)
            }
            if succeeded { dismiss() }
        }
    }
}
