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

struct GitProviderAddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: GitProviderAccountController
    private let editingAccount: GitProviderAccount?
    private let accountCreationDecision: GitProviderAccountCreationDecision

    @State private var selectedHost: GitProviderAddAccountHost = .github
    @State private var selectedAuthType: GitProviderAddAccountAuthType = .oauth
    @State private var selectedProtocol: GitProviderAddAccountProtocol = .https
    @State private var isSelfHosted = false
    @State private var serverURL = ""
    @State private var personalAccessToken = ""
    @State private var connectedAccountID: String?
    @State private var connectedUsername = ""
    @State private var bitbucketUsername = ""
    @State private var bitbucketAPIToken = ""
    @State private var azureOrganization = ""
    @State private var sshKeyPath = ""
    @State private var connectionTask: Task<Void, Never>?
    /// This view started a GitHub or GitLab browser authorization whose account has not arrived yet.
    @State private var awaitsBrowserResult = false

    init(
        controller: GitProviderAccountController,
        editingAccount: GitProviderAccount? = nil,
        accountCreationDecision: GitProviderAccountCreationDecision = .allowed
    ) {
        self.controller = controller
        self.editingAccount = editingAccount
        self.accountCreationDecision = accountCreationDecision
        if let account = editingAccount {
            let publicHost = account.provider == .github ? GitProviderHost.githubDotCom : GitProviderHost.gitlabDotCom
            _isSelfHosted = State(initialValue: account.provider != .bitbucket && account.provider != .azureDevOps
                && account.hostURL != publicHost.baseURL)
            _serverURL = State(initialValue: account.hostURL.absoluteString)
        }
        _selectedHost = State(initialValue: editingAccount.map(GitProviderAddAccountPresentationPolicy.host(for:)) ?? .github)
        _selectedAuthType = State(initialValue: GitProviderAddAccountPresentationPolicy.initialAuthType(for: editingAccount))
        _selectedProtocol = State(initialValue: editingAccount?.transportProtocol == .ssh ? .ssh : .https)
        _connectedAccountID = State(initialValue: editingAccount?.id)
        _connectedUsername = State(initialValue: editingAccount?.username ?? "")
        _bitbucketUsername = State(initialValue: editingAccount?.provider == .bitbucket ? editingAccount?.username ?? "" : "")
        _azureOrganization = State(initialValue: editingAccount?.provider == .azureDevOps ? editingAccount?.hostURL.lastPathComponent ?? "" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()

            Form {
                Picker("Host", selection: $selectedHost) {
                    ForEach(GitProviderAddAccountPresentationPolicy.hostOptions, id: \.id) { option in
                        Text(option.title)
                            .tag(option.id)
                            .disabled(!option.isEnabled)
                    }
                }
                .disabled(editingAccount != nil)
                .onChange(of: selectedHost) { _, _ in
                    connectedUsername = ""
                    connectedAccountID = nil
                    isSelfHosted = false
                    serverURL = ""
                    personalAccessToken = ""
                    bitbucketUsername = ""
                    bitbucketAPIToken = ""
                    azureOrganization = ""
                    selectedAuthType = GitProviderAddAccountPresentationPolicy.usesTokenOnly(selectedHost) ? .personalAccessToken : .oauth
                }

                if !GitProviderAddAccountPresentationPolicy.usesTokenOnly(selectedHost) {
                    Toggle("Self-hosted server (Pro)", isOn: $isSelfHosted)
                        .disabled(editingAccount != nil || !controller.canConnectSelfHosted)
                        .onChange(of: isSelfHosted) { _, _ in
                            connectedUsername = ""
                            connectedAccountID = nil
                            personalAccessToken = ""
                        }
                    if !controller.canConnectSelfHosted {
                        Text("Connecting self-managed Git servers requires an active Pro plan.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isSelfHosted {
                        TextField("Server URL", text: $serverURL, prompt: Text("https://git.company.com"))
                            .disabled(editingAccount != nil)
                            .onChange(of: serverURL) { _, _ in
                                connectedUsername = ""
                                connectedAccountID = nil
                                personalAccessToken = ""
                            }
                        if selectedProtocol == .https {
                            SecureField("Personal Access Token", text: $personalAccessToken)
                            Text(selectedHost == .github
                                 ? "Use a token with access to the repository and required pull request permissions."
                                 : "Use a personal access token with api scope for API access and Git operations.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !isSelfHosted {
                    Picker("Auth Type", selection: $selectedAuthType) {
                        ForEach(GitProviderAddAccountPresentationPolicy.authTypeOptions(for: selectedHost), id: \.id) { option in
                            Text(option.title)
                                .tag(option.id)
                                .disabled(!option.isEnabled)
                        }
                    }
                    .disabled(!GitProviderAddAccountPresentationPolicy.canSelectAuthType(for: selectedHost))
                    .onChange(of: selectedAuthType) { _, _ in
                        personalAccessToken = ""
                    }

                    if usesPublicPersonalAccessToken {
                        SecureField("Personal Access Token", text: $personalAccessToken)
                        Text(selectedHost == .github
                             ? "Use a token with repo scope, or a fine-grained token with Contents and Pull requests read and write access."
                             : "Use a personal access token with api scope for API access and Git operations.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Create Personal Access Token", action: openPersonalAccessTokenPage)
                            .buttonStyle(.link)
                    }
                }

                if selectedHost == .bitbucket {
                    TextField("Username", text: $bitbucketUsername)
                        .disabled(editingAccount != nil)
                    if selectedProtocol == .https {
                        SecureField("API Token", text: $bitbucketAPIToken)
                        Text("Requires read:repository:bitbucket and write:repository:bitbucket scopes.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Get API Token", action: openBitbucketAPITokenPage)
                            .buttonStyle(.link)
                    }
                } else if selectedHost == .azureDevOps {
                    TextField("Organization", text: $azureOrganization, prompt: Text(verbatim: "my-organization"))
                        .disabled(editingAccount != nil)
                        .onChange(of: azureOrganization) { _, _ in
                            connectedUsername = ""
                            connectedAccountID = nil
                        }
                    if !azureOrganization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, azureOrganizationName == nil {
                        Text("Enter an Azure DevOps organization name or URL.")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // Verbatim so the example URL is not rendered as a link that looks like an entered value.
                        Text(verbatim: "Organization name, or a URL such as https://dev.azure.com/my-organization.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if selectedProtocol == .https {
                        SecureField("Personal Access Token", text: $personalAccessToken)
                        Text(hasStoredAzureToken
                             ? "A personal access token is saved for this account. Enter a new one only to replace it."
                             : "Requires Code (Read & Write) scope.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Get Personal Access Token", action: openAzureDevOpsTokenPage)
                            .buttonStyle(.link)
                    }
                    LabeledContent("Username") {
                        Text(GitProviderAddAccountPresentationPolicy.usernameDisplayText(for: connectedUsername))
                            .foregroundStyle(connectedUsername.isEmpty ? .secondary : .primary)
                    }
                } else {
                    LabeledContent("Username") {
                        Text(GitProviderAddAccountPresentationPolicy.usernameDisplayText(for: connectedUsername))
                            .foregroundStyle(connectedUsername.isEmpty ? .secondary : .primary)
                    }
                }

                if selectedProtocol == .https {
                    Button(connectButtonTitle, action: connectAccount)
                        .disabled(!canConnect || controller.isLoading || controller.awaitingBrowserAuthorizationProvider != nil)
                }

                Picker("Protocol", selection: $selectedProtocol) {
                    ForEach(GitProviderAddAccountPresentationPolicy.protocolOptions, id: \.id) { option in
                        Text(option.title)
                            .tag(option.id)
                            .disabled(!option.isEnabled)
                    }
                }

                if selectedProtocol == .ssh {
                    LabeledContent("SSH Key") {
                        HStack {
                            Text(sshKeyPath.isEmpty ? "_" : abbreviatedPath(sshKeyPath))
                                .foregroundStyle(sshKeyPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button("Choose...", action: chooseSSHKey)
                        }
                    }

                    if selectedHost == .azureDevOps {
                        Text("Azure DevOps accepts RSA SSH keys only. Your personal access token stays saved for switching back to HTTPS.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(connectButtonTitle, action: connectAccount)
                        .disabled(!canConnect || controller.isLoading || sshKeyPath.isEmpty)
                }
            }
            .formStyle(.grouped)
            // Inline, the grouped card sits directly on the settings pane instead of a second backdrop.
            .disabled(controller.isLoading)

            if awaitsBrowserResult, controller.awaitingBrowserAuthorizationProvider != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Finish connecting in your browser…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", action: cancelConnection)
                    }
                    Button("Use a device code instead", action: useDeviceCode)
                        .buttonStyle(.link)
                }
            }

            if let authorization = controller.pendingDeviceAuthorization {
                GitProviderDeviceAuthorizationView(
                    authorization: authorization,
                    openVerification: controller.openPendingDeviceVerification,
                    copyToPasteboard: copyToPasteboard,
                    cancel: cancelConnection
                )
            }

            if controller.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Connecting account...")
                        .controlSize(.small)
                    Spacer()
                }
            }

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if editingAccount == nil,
               matchingAccount() == nil,
               let message = GitProviderAccountsPresentationPolicy.accountCreationMessage(
                   for: accountCreationDecision
               ) {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Need help logging into your account?", action: openGitProviderHelpPage)
                    .buttonStyle(.link)

                Spacer()

                Button("Cancel", action: cancel)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding()
        .frame(minWidth: 540, minHeight: 360)
        .onAppear(perform: loadExistingSSHKey)
        .onDisappear(perform: cancelConnection)
        // The browser flow completes from the URL callback, after `connectAccount` returned.
        .onChange(of: controller.accounts.map(\.id)) { _, _ in
            guard awaitsBrowserResult else { return }
            awaitsBrowserResult = false
            refreshConnectedUsername()
        }
    }

    private var configuredHost: GitProviderHost? {
        let kind: GitProviderKind = switch selectedHost {
        case .github: .github
        case .gitlab: .gitlab
        case .bitbucket: .bitbucket
        case .azureDevOps: .azureDevOps
        }
        if isSelfHosted { return GitProviderHost.configured(kind: kind, value: serverURL) }
        switch kind {
        case .github: return .githubDotCom
        case .gitlab: return .gitlabDotCom
        case .bitbucket: return .bitbucketDotOrg
        case .azureDevOps:
            return azureOrganizationName.map { GitProviderHost(kind: .azureDevOps, baseURL: AzureReposRemote.organizationURL($0)) }
        }
    }

    private var hasStoredAzureToken: Bool {
        guard selectedHost == .azureDevOps, let account = matchingAccount() ?? editingAccount else { return false }
        return controller.hasStoredToken(for: account)
    }

    private var azureOrganizationName: String? {
        AzureReposRemote.organization(fromInput: azureOrganization)
    }

    private var canConnect: Bool {
        if isSelfHosted {
            return controller.canConnectSelfHosted && (editingAccount != nil || accountCreationDecision.isAllowed) && configuredHost != nil
                && (selectedProtocol == .ssh ? !sshKeyPath.isEmpty : !personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        guard (editingAccount != nil || accountCreationDecision.isAllowed),
              GitProviderAddAccountPresentationPolicy.canConnect(
            host: selectedHost,
            authType: selectedAuthType,
            protocol: selectedProtocol
        ) else {
            return false
        }
        if usesPublicPersonalAccessToken {
            return !personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if selectedHost == .azureDevOps {
            guard azureOrganizationName != nil else { return false }
            return selectedProtocol == .ssh
                ? !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : !personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard selectedHost == .bitbucket else { return true }
        guard !bitbucketUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if selectedProtocol == .ssh {
            return !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !bitbucketAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// GitHub.com or GitLab.com over HTTPS with a token instead of the OAuth flow.
    private var usesPublicPersonalAccessToken: Bool {
        !isSelfHosted && !GitProviderAddAccountPresentationPolicy.usesTokenOnly(selectedHost) && selectedProtocol == .https && selectedAuthType == .personalAccessToken
    }

    private var connectButtonTitle: String {
        GitProviderAddAccountPresentationPolicy.connectButtonTitle(
            connectedUsername: connectedUsername,
            protocol: selectedProtocol
        )
    }

    private var canSave: Bool {
        // An Azure account switched back to HTTPS needs a PAT on this Mac, kept from before or entered now.
        if selectedHost == .azureDevOps, selectedProtocol == .https, !hasStoredAzureToken {
            return false
        }
        return (editingAccount != nil || matchingAccount() != nil || accountCreationDecision.isAllowed)
            && GitProviderAddAccountPresentationPolicy.canSave(
            connectedUsername: connectedUsername,
            protocol: selectedProtocol,
            sshKeyPath: sshKeyPath
        )
    }

    private var title: String {
        editingAccount == nil ? "Add Account" : "Edit Account"
    }

    private func connectAccount() {
        guard canConnect else { return }
        connectionTask?.cancel()
        connectionTask = Task { @MainActor in
            if isSelfHosted, let host = configuredHost {
                if selectedProtocol == .ssh {
                    await controller.connectSSH(host: host, key: GitProviderSSHKey(path: sshKeyPath), replacing: editingAccount)
                } else {
                    await controller.connectPersonalAccessToken(host: host, accessToken: personalAccessToken, replacing: editingAccount)
                    if controller.errorMessage == nil { personalAccessToken = "" }
                }
            } else if usesPublicPersonalAccessToken, let host = configuredHost {
                await controller.connectPersonalAccessToken(host: host, accessToken: personalAccessToken, replacing: editingAccount)
                if controller.errorMessage == nil { personalAccessToken = "" }
            } else {
                switch selectedHost {
                case .github:
                    if selectedProtocol == .ssh {
                        await controller.connectSSH(host: .githubDotCom, key: GitProviderSSHKey(path: sshKeyPath), replacing: editingAccount)
                    } else if let editingAccount {
                        await controller.reconnect(editingAccount)
                    } else {
                        await controller.connectGitHub()
                    }
                case .gitlab:
                    if selectedProtocol == .ssh {
                        await controller.connectSSH(host: .gitlabDotCom, key: GitProviderSSHKey(path: sshKeyPath), replacing: editingAccount)
                    } else if let editingAccount {
                        await controller.reconnect(editingAccount)
                    } else {
                        await controller.connectGitLabDotCom()
                    }
                case .bitbucket:
                    if selectedProtocol == .ssh {
                        await controller.connectSSH(
                            host: .bitbucketDotOrg,
                            key: GitProviderSSHKey(path: sshKeyPath),
                            username: bitbucketUsername,
                            replacing: editingAccount
                        )
                    } else {
                        await controller.connectBitbucket(
                            username: bitbucketUsername,
                            apiToken: bitbucketAPIToken,
                            replacing: editingAccount
                        )
                        if controller.errorMessage == nil {
                            bitbucketAPIToken = ""
                        }
                    }
                case .azureDevOps:
                    guard let organization = azureOrganizationName, let host = configuredHost else { break }
                    if selectedProtocol == .ssh {
                        await controller.connectSSH(
                            host: host,
                            key: GitProviderSSHKey(path: sshKeyPath),
                            username: organization,
                            replacing: editingAccount
                        )
                    } else {
                        await controller.connectAzureDevOps(
                            organization: organization,
                            accessToken: personalAccessToken,
                            replacing: editingAccount
                        )
                        if controller.errorMessage == nil { personalAccessToken = "" }
                    }
                }
            }
            awaitsBrowserResult = controller.awaitingBrowserAuthorizationProvider != nil
            refreshConnectedUsername()
            connectionTask = nil
        }
    }

    private func useDeviceCode() {
        let provider = controller.awaitingBrowserAuthorizationProvider
        awaitsBrowserResult = false
        connectionTask?.cancel()
        connectionTask = Task { @MainActor in
            if provider == .gitlab {
                await controller.connectGitLabWithDeviceCode()
            } else {
                await controller.connectGitHubWithDeviceCode()
            }
            refreshConnectedUsername()
            connectionTask = nil
        }
    }

    private func refreshConnectedUsername() {
        guard controller.errorMessage == nil, let host = configuredHost else { return }
        let account = controller.accounts.last { $0.provider == host.kind && GitProviderHost.identityKey($0.hostURL) == GitProviderHost.identityKey(host.baseURL) }
        connectedAccountID = account?.id
        connectedUsername = account?.username ?? ""
    }

    private func matchingAccount() -> GitProviderAccount? {
        guard let host = configuredHost else { return nil }
        return controller.accounts.first { account in
            account.id == connectedAccountID && account.provider == host.kind && GitProviderHost.identityKey(account.hostURL) == GitProviderHost.identityKey(host.baseURL)
                && (editingAccount == nil || account.providerUserID == editingAccount?.providerUserID)
        }
    }

    private func cancel() {
        cancelConnection()
        dismiss()
    }

    private func save() {
        guard canSave, let account = matchingAccount() ?? editingAccount else { return }
        let transportProtocol: GitProviderTransportProtocol = selectedProtocol == .ssh ? .ssh : .https
        let sshKey = selectedProtocol == .ssh ? GitProviderSSHKey(path: sshKeyPath) : nil
        Task { @MainActor in
            await controller.saveConnectionSettings(
                account: account,
                transportProtocol: transportProtocol,
                sshKey: sshKey
            )
            // Stay open on failure so the error shows here and the user can fix it.
            if controller.errorMessage == nil { dismiss() }
        }
    }

    private func cancelConnection() {
        connectionTask?.cancel()
        connectionTask = nil
        if awaitsBrowserResult {
            awaitsBrowserResult = false
            controller.cancelBrowserAuthorization()
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func openBitbucketAPITokenPage() {
        guard let url = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openAzureDevOpsTokenPage() {
        let address = azureOrganizationName.map { "https://dev.azure.com/\($0)/_usersSettings/tokens" }
            ?? "https://aex.dev.azure.com/"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openPersonalAccessTokenPage() {
        let address = selectedHost == .github
            ? "https://github.com/settings/tokens"
            : "https://gitlab.com/-/user_settings/personal_access_tokens?name=Commit%2B&scopes=api"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openGitProviderHelpPage() {
        do {
            let url = try CommitPlusWebConfiguration.baseURL()
                .appending(path: "blog")
                .appending(path: "connect-git-provider-accounts")
            guard NSWorkspace.shared.open(url) else {
                throw WebAccountSessionError.unableToOpenBrowser
            }
        } catch {
            controller.errorMessage = error.localizedDescription
        }
    }

    private func loadExistingSSHKey() {
        guard let editingAccount,
              let key = try? controller.sshKey(for: editingAccount) else {
            return
        }
        sshKeyPath = key.path
    }

    private func chooseSSHKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        if panel.runModal() == .OK, let url = panel.url {
            sshKeyPath = url.path
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else {
            return path
        }
        return "~" + path.dropFirst(home.count)
    }
}
