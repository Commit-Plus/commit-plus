//
//  RepositorySettingsSheetView.swift
//  macgit
//

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

enum RepositorySettingsTab: String, CaseIterable, Identifiable {
    case remote = "Remote"
    case pullFetch = "Pull & Fetch"
    case gitFlow = "Git Flow"
    case advanced = "Advanced"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .remote: "network"
        case .pullFetch: "arrow.triangle.2.circlepath"
        case .gitFlow: "arrow.triangle.branch"
        case .advanced: "gearshape.2"
        }
    }
}

struct RemoteInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: String
}

struct ProviderRemoteAccountOption: Identifiable {
    let remoteName: String
    let identity: GitRemoteIdentity
    let accounts: [GitProviderAccount]

    var id: String {
        GitProviderAccountPreferenceKey.make(for: identity)
    }
}

struct RepositorySettingsSheetView: View {
    @EnvironmentObject private var appState: AppState

    let repositoryURL: URL
    let onClose: () -> Void
    let initialSettings: RepoSettings
    let initialGitFlowConfiguration: GitFlowConfiguration
    let initiallySelectGitFlow: Bool
    let hasInvalidGitFlowConfiguration: Bool
    let providerAccountResolver: GitProviderCredentialResolver
    let providerAccountPreferences: [String: String]
    let onSave: (RepoSettings) -> Void
    let onSaveGitFlowConfiguration: @MainActor (GitFlowConfiguration) async -> Bool
    let onAuthorizeGitFlowAccess: @MainActor () async -> Bool
    let onCreateGitFlowDevelopBranch: @MainActor (GitFlowDevelopBranchRequest) async throws -> String
    let onSaveProviderAccountPreferences: ([String: String?]) -> Void
    let onOpenGitIgnore: () -> Void
    let onOpenGitConfig: () -> Void
    let onOpenRemoteURL: (String) -> Void

    @State private var selectedTab: RepositorySettingsTab = .remote
    @State private var draft: RepositorySettingsDraft?
    @State private var remotes: [String] = []
    @State private var branches: [String] = []
    @State private var remoteURLs: [String: String] = [:]
    @State private var selectedRemoteName: String = ""
    @State private var showingRemoteEditSheet = false
    @State private var remoteEditMode: RemoteEditMode = .add
    @State private var selectedProviderAccountIDs: [String: String] = [:]
    @State private var gitFlowConfiguration = GitFlowConfiguration()
    @State private var showingCreateDevelopBranchSheet = false
    @State private var isGitFlowTabAuthorized = false
    @State private var isAuthorizingGitFlowTab = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let draft {
                    Group {
                        switch selectedTab {
                        case .remote:
                            remoteTab(draft)
                        case .pullFetch:
                            pullFetchTab
                        case .gitFlow:
                            if isGitFlowTabAuthorized {
                                gitFlowTab
                            } else {
                                VStack(spacing: 10) {
                                    ProgressView()
                                    Text("Checking Git Flow access…")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 220)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Checking Git Flow access")
                            }
                        case .advanced:
                            advancedTab
                        }
                    }
                } else {
                    VStack {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .padding(24)
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(minWidth: 600, idealWidth: 640, maxWidth: .infinity)
        .frame(minHeight: 480, idealHeight: 540)
        .background(RepositorySettingsToolbar(selection: $selectedTab))
        .task {
            await loadOptions()
        }
        .onChange(of: initiallySelectGitFlow, initial: true) { _, shouldSelectGitFlow in
            guard shouldSelectGitFlow else { return }
            selectedTab = .gitFlow
            authorizeGitFlowTab(fallback: .remote)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            guard newTab == .gitFlow else { return }
            authorizeGitFlowTab(fallback: oldTab)
        }
        .replacingSheet(isPresented: $showingRemoteEditSheet) {
            RemoteEditSheetView(
                repositoryURL: repositoryURL,
                mode: remoteEditMode
            ) { name, url in
                Task {
                    await handleRemoteSave(name: name, url: url)
                }
            }
        }
        .replacingSheet(isPresented: $showingCreateDevelopBranchSheet) {
            CreateGitFlowDevelopBranchSheet(
                suggestedName: suggestedDevelopBranchName,
                startingPoint: gitFlowConfiguration.mainBranch,
                onCreate: onCreateGitFlowDevelopBranch,
                onCreated: selectCreatedDevelopBranch
            )
        }
    }

    private func authorizeGitFlowTab(fallback: RepositorySettingsTab) {
        guard !isGitFlowTabAuthorized, !isAuthorizingGitFlowTab else { return }
        isAuthorizingGitFlowTab = true
        Task {
            let isAllowed = await onAuthorizeGitFlowAccess()
            await MainActor.run {
                isAuthorizingGitFlowTab = false
                isGitFlowTabAuthorized = isAllowed
                if !isAllowed, selectedTab == .gitFlow {
                    selectedTab = fallback == .gitFlow ? .remote : fallback
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel", role: .cancel) {
                onClose()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save", action: save)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding(16)
    }

    private func save() {
        guard let draft else { return }
        Task {
            if (gitFlowConfiguration != initialGitFlowConfiguration || hasInvalidGitFlowConfiguration),
               await onSaveGitFlowConfiguration(gitFlowConfiguration.normalized()) == false {
                return
            }
            await MainActor.run {
                onSave(draft.resolvedSettings)
                onSaveProviderAccountPreferences(providerAccountPreferenceChanges)
                onClose()
            }
        }
    }

    @ViewBuilder
    private func remoteTab(_ draft: RepositorySettingsDraft) -> some View {
        Section("Remote repository paths") {
            remoteTable
        }

        Section("Defaults") {
            Picker("Default remote", selection: binding(\.selectedRemoteName)) {
                ForEach(remoteOptions(for: draft), id: \.self) { remote in
                    Text(remote).tag(remote)
                }
            }
            .disabled(remoteOptions(for: draft).isEmpty)

            Picker("Default pull branch", selection: binding(\.selectedBranchMode)) {
                Text("Detected branch").tag(SelectedBranchMode.detected)
                Text("Manual entry").tag(SelectedBranchMode.manual)
            }

            if draft.selectedBranchMode == .detected {
                LabeledContent("Branch") {
                    SearchableReferencePicker(
                        title: "Default pull branch", selection: draft.selectedDetectedBranch,
                        options: branchOptions(for: draft), searchPrompt: "Search branches",
                        onSelect: { binding(\.selectedDetectedBranch).wrappedValue = $0 })
                        .disabled(branchOptions(for: draft).isEmpty)
                }
            } else {
                TextField("Branch", text: binding(\.manualBranchName), prompt: Text("release/hotfix"))
            }
        }

        Section {
        } footer: {
            SettingsActionRow {
                Button("Open Remote URL") {
                    guard !draft.selectedRemoteName.isEmpty else { return }
                    onOpenRemoteURL(draft.selectedRemoteName)
                }
                .disabled(draft.selectedRemoteName.isEmpty)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .buttonStyle(.bordered)
        }
    }

    private var remoteTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("Name")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 100, alignment: .leading)
                        .padding(.horizontal, 8)

                    Divider()

                    Text("Path")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)

                    Spacer()
                }
                .frame(height: 28)
                .background(.quaternary.opacity(0.2))

                Divider()

                // Rows
                ForEach(remotes.map { RemoteInfo(name: $0, url: remoteURLs[$0] ?? "") }) { remote in
                    HStack(spacing: 0) {
                        Text(remote.name)
                            .font(.system(size: 12))
                            .frame(width: 100, alignment: .leading)
                            .padding(.horizontal, 8)

                        Divider()

                        Text(remote.url)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .frame(height: 28)
                    .background(selectedRemoteName == remote.name ? Color.accentColor.opacity(0.15) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRemoteName = remote.name
                    }

                    Divider()
                }
            }
            .background(.quaternary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(.quaternary.opacity(0.4), lineWidth: 1)
            )

            SettingsActionRow {
                Button("Add") {
                    remoteEditMode = .add
                    showingRemoteEditSheet = true
                }

                Button("Edit") {
                    guard let url = remoteURLs[selectedRemoteName], !selectedRemoteName.isEmpty else { return }
                    remoteEditMode = .edit(name: selectedRemoteName, url: url)
                    showingRemoteEditSheet = true
                }
                .disabled(selectedRemoteName.isEmpty)

                Button("Remove", role: .destructive) {
                    Task {
                        await removeRemote(name: selectedRemoteName)
                    }
                }
                .disabled(selectedRemoteName.isEmpty)
            }
            .buttonStyle(.bordered)
        }
    }

    private var pullFetchTab: some View {
        Section("Pull & Fetch") {
            Picker("Pull strategy", selection: binding(\.pullStrategy)) {
                Text("Merge").tag(PullStrategy.merge)
                Text("Rebase").tag(PullStrategy.rebase)
            }
            Picker("Auto fetch", selection: binding(\.autoFetchOverride)) {
                Text(globalOptionTitle(value: appState.autoFetchEnabled)).tag(Bool?.none)
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            }
            Picker("Refresh when app becomes active", selection: binding(\.refreshOnAppActiveOverride)) {
                Text(globalOptionTitle(value: appState.refreshOnAppActive)).tag(Bool?.none)
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            }
        }
    }

    private var advancedTab: some View {
        Group {
            Section("Safety & Confirmations") {
                Toggle("Confirm detached HEAD checkout", isOn: binding(\.confirmDetachedHeadCheckout))
                Toggle("Skip protected branch commit warnings", isOn: binding(\.skipProtectedBranchCommitWarnings))
                    .help("Skip local commit warnings for this repository. Remote branch protection still applies when pushing.")
                Toggle("Confirm destructive stash actions", isOn: binding(\.confirmDestructiveStashActions))
            }

            userInformationSection
            providerAccountSection

            Section {
            } footer: {
                SettingsActionRow {
                    Button("Open .gitignore", action: onOpenGitIgnore)
                    Button("Open .git/config", action: onOpenGitConfig)
                }
                .font(.body)
                .foregroundStyle(.primary)
                .buttonStyle(.bordered)
            }
        }
    }

    private var gitFlowTab: some View {
        Group {
            Section("Git Flow") {
                Toggle("Enable Git Flow", isOn: $gitFlowConfiguration.isEnabled)
            }

            Section("Branches") {
                branchPicker(
                    title: "Main branch",
                    selection: $gitFlowConfiguration.mainBranch
                )
                branchPicker(
                    title: "Develop branch",
                    selection: $gitFlowConfiguration.developBranch,
                    showsCreateDevelopBranchButton: shouldOfferCreateDevelopBranch
                )
            }
            .disabled(!gitFlowConfiguration.isEnabled)

            Section("Branch Prefixes") {
                prefixField("Feature", text: $gitFlowConfiguration.featurePrefix)
                prefixField("Bugfix", text: $gitFlowConfiguration.bugfixPrefix)
                prefixField("Release", text: $gitFlowConfiguration.releasePrefix)
                prefixField("Hotfix", text: $gitFlowConfiguration.hotfixPrefix)
            }
            .disabled(!gitFlowConfiguration.isEnabled)

            Section {
                Picker("Start new flows in", selection: $gitFlowConfiguration.defaultStartDestination) {
                    ForEach(GitFlowStartDestination.allCases) { destination in
                        Text(destination.displayName).tag(destination)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Default Git Flow start destination")
                .accessibilityValue(gitFlowConfiguration.defaultStartDestination.displayName)

            } header: {
                Text("Start Behavior")
            } footer: {
                Text("This is the default. You can change the destination for each flow from the Start sheet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(!gitFlowConfiguration.isEnabled)

            Section {
                Picker("Feature & Bugfix", selection: $gitFlowConfiguration.topicFinishStrategy) {
                    ForEach(GitFlowTopicFinishStrategy.allCases) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Default Feature and Bugfix finish strategy")
                .accessibilityValue(gitFlowConfiguration.topicFinishStrategy.displayName)

                Toggle(
                    "Create an annotated tag when finishing Release",
                    isOn: $gitFlowConfiguration.createReleaseTagOnFinish
                )
                Toggle(
                    "Create an annotated tag when finishing Hotfix",
                    isOn: $gitFlowConfiguration.createHotfixTagOnFinish
                )

            } header: {
                Text("Finish Behavior")
            } footer: {
                Text("Release and Hotfix always merge into Main, then Develop. Tag names default to the branch suffix.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(!gitFlowConfiguration.isEnabled)

            if let validationMessage = gitFlowValidationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else if gitFlowConfiguration.isEnabled {
                Text("Feature, Bugfix, and Release start from Develop. Hotfix starts from Main.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func branchPicker(
        title: String,
        selection: Binding<String>,
        showsCreateDevelopBranchButton: Bool = false
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                SearchableReferencePicker(
                    title: title, selection: selection.wrappedValue,
                    options: branches, searchPrompt: "Search branches",
                    onSelect: { selection.wrappedValue = $0 })
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180)

                if showsCreateDevelopBranchButton {
                    Button("Create New…") {
                        showingCreateDevelopBranchSheet = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(gitFlowConfiguration.mainBranch.isEmpty)
                }
            }
        }
    }

    private var shouldOfferCreateDevelopBranch: Bool {
        let selectedDevelopBranch = gitFlowConfiguration.developBranch
        return gitFlowConfiguration.isEnabled
            && (selectedDevelopBranch.isEmpty || !branches.contains(selectedDevelopBranch))
    }

    private var suggestedDevelopBranchName: String {
        let selectedDevelopBranch = gitFlowConfiguration.developBranch
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return selectedDevelopBranch.isEmpty ? "develop" : selectedDevelopBranch
    }

    private func selectCreatedDevelopBranch(_ branch: String) {
        if !branches.contains(branch) {
            branches.append(branch)
            branches.sort()
        }
        gitFlowConfiguration.developBranch = branch
    }

    private func prefixField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text("\(title.lowercased())/"))
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
    }

    private var gitFlowValidationMessage: String? {
        guard gitFlowConfiguration.isEnabled else { return nil }
        do {
            try GitFlowPlanner().validate(gitFlowConfiguration)
            let normalized = gitFlowConfiguration.normalized()
            guard branches.contains(normalized.mainBranch) else {
                return "The selected Main branch does not exist."
            }
            guard branches.contains(normalized.developBranch) else {
                return "The selected Develop branch does not exist."
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canSave: Bool {
        draft != nil && gitFlowValidationMessage == nil
    }

    private var userInformationSection: some View {
        Section("User Information") {
            Toggle("Use global user settings", isOn: binding(\.useGlobalUserSettings))
            TextField("Full Name", text: binding(\.userName))
                .disabled(draft?.useGlobalUserSettings == true)
            TextField("Email address", text: binding(\.userEmail))
                .disabled(draft?.useGlobalUserSettings == true)
        }
    }

    @ViewBuilder
    private var providerAccountSection: some View {
        let options = providerRemoteAccountOptions
        if !options.isEmpty {
            Section {
                ForEach(options) { option in
                    LabeledContent {
                        Picker("Account for \(option.remoteName)", selection: providerAccountSelectionBinding(for: option)) {
                            Text("Automatic").tag("")
                            ForEach(option.accounts) { account in
                                Text(accountDisplayName(account)).tag(account.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.remoteName)
                            Text(option.identity.canonicalHTTPSURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            } header: {
                Text("Git Provider Accounts")
            } footer: {
                Text("Choose which connected account this remote uses. Automatic uses the only matching account and asks before a remote operation when more than one account matches.")
            }
        }
    }

    private func loadOptions() async {
        async let loadedRemotes = GitStatusService.shared.remotes(in: repositoryURL)
        async let loadedBranches = GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
        async let loadedCurrentBranch = GitStatusService.shared.currentBranch(in: repositoryURL)

        let (loadedRemotesValue, loadedBranchesValue, currentBranch) = await (
            loadedRemotes,
            loadedBranches,
            loadedCurrentBranch
        )

        // Load remote URLs
        var urls: [String: String] = [:]
        for remote in loadedRemotesValue {
            if let url = try? await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL) {
                urls[remote] = url
            }
        }

        let localUser = await GitStatusService.shared.gitUserConfiguration(in: repositoryURL, scope: .local)
        let globalUser = await GitStatusService.shared.gitUserConfiguration(in: repositoryURL, scope: .global)
        var settings = initialSettings
        settings.useGlobalUserSettings = localUser == nil
        settings.userName = (settings.useGlobalUserSettings ? globalUser?.name : localUser?.name) ?? ""
        settings.userEmail = (settings.useGlobalUserSettings ? globalUser?.email : localUser?.email) ?? ""

        await MainActor.run {
            remotes = loadedRemotesValue
            branches = loadedBranchesValue
            remoteURLs = urls
            selectedRemoteName = loadedRemotesValue.first ?? ""
            draft = RepositorySettingsDraft(
                settings: settings,
                remotes: loadedRemotesValue,
                branches: loadedBranchesValue,
                currentBranch: currentBranch
            )
            gitFlowConfiguration = initialGitFlowConfiguration
            selectedProviderAccountIDs = validProviderAccountPreferences
        }
    }

    private var providerRemoteAccountOptions: [ProviderRemoteAccountOption] {
        remotes.compactMap { remoteName in
            guard let remoteURL = remoteURLs[remoteName],
                  let identity = providerAccountResolver.remoteIdentity(for: remoteURL) else {
                return nil
            }
            let accounts = providerAccountResolver.matchingAccounts(for: remoteURL)
            guard !accounts.isEmpty else { return nil }
            return ProviderRemoteAccountOption(
                remoteName: remoteName,
                identity: identity,
                accounts: accounts
            )
        }
    }

    private var validProviderAccountPreferences: [String: String] {
        providerRemoteAccountOptions.reduce(into: providerAccountPreferences) { preferences, option in
            guard let accountID = preferences[option.id],
                  !option.accounts.contains(where: { $0.id == accountID }) else {
                return
            }
            preferences.removeValue(forKey: option.id)
        }
    }

    private var providerAccountPreferenceChanges: [String: String?] {
        providerRemoteAccountOptions.reduce(into: [String: String?]()) { changes, option in
            let selectedAccountID = selectedProviderAccountIDs[option.id]
            changes[option.id] = selectedAccountID?.isEmpty == false ? selectedAccountID : nil
        }
    }

    private func providerAccountSelectionBinding(
        for option: ProviderRemoteAccountOption
    ) -> Binding<String> {
        Binding(
            get: { selectedProviderAccountIDs[option.id] ?? "" },
            set: { accountID in
                if accountID.isEmpty {
                    selectedProviderAccountIDs.removeValue(forKey: option.id)
                } else {
                    selectedProviderAccountIDs[option.id] = accountID
                }
            }
        )
    }

    private func accountDisplayName(_ account: GitProviderAccount) -> String {
        let host = account.hostURL.host(percentEncoded: false) ?? account.hostURL.absoluteString
        return "\(account.provider.displayName) · \(account.username) · \(host)"
    }

    private func handleRemoteSave(name: String, url: String) async {
        switch remoteEditMode {
        case .add:
            do {
                try await GitStatusService.shared.addRemote(name: name, url: url, in: repositoryURL)
                await loadOptions()
                await MainActor.run {
                    selectedRemoteName = name
                }
            } catch {
                // Silently handle for now — could show an alert in future
            }
        case .edit(let oldName, _):
            do {
                try await GitStatusService.shared.setRemoteURL(name: oldName, url: url, in: repositoryURL)
                await loadOptions()
            } catch {
                // Silently handle for now
            }
        }
    }

    private func removeRemote(name: String) async {
        guard !name.isEmpty else { return }
        do {
            try await GitStatusService.shared.removeRemote(name: name, in: repositoryURL)
            await loadOptions()
        } catch {
            // Silently handle for now
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RepositorySettingsDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft![keyPath: keyPath] },
            set: { newValue in
                draft![keyPath: keyPath] = newValue
            }
        )
    }

    private func globalOptionTitle(value: Bool) -> String {
        "Use Global (\(value ? "On" : "Off"))"
    }

    private func remoteOptions(for draft: RepositorySettingsDraft) -> [String] {
        let candidates = remotes.isEmpty ? draft.remotes : remotes
        if draft.selectedRemoteName.isEmpty || candidates.contains(draft.selectedRemoteName) {
            return candidates
        }
        return [draft.selectedRemoteName] + candidates
    }

    private func branchOptions(for draft: RepositorySettingsDraft) -> [String] {
        let candidates = branches.isEmpty ? draft.branches : branches
        if draft.selectedDetectedBranch.isEmpty || candidates.contains(draft.selectedDetectedBranch) {
            return candidates
        }
        return [draft.selectedDetectedBranch] + candidates
    }
}
