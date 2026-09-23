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

private enum RepositorySettingsTab: String, CaseIterable, Identifiable {
    case remote = "Remote"
    case pullFetch = "Pull & Fetch"
    case gitFlow = "Git Flow"
    case advanced = "Advanced"

    var id: String { rawValue }
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let repositoryURL: URL
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
    private let settingsContentWidth: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .padding(.top, 12)

            ScrollView {
                if let draft {
                    VStack(alignment: .center, spacing: 16) {
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
                    .padding(16)
                    .frame(maxWidth: settingsContentWidth, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .padding(24)
                }
            }

            footer
        }
        .frame(minWidth: 600, idealWidth: 640, maxWidth: 680)
        .frame(minHeight: 420, idealHeight: 480)
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

    private var header: some View {
        HStack {
            Text("Repository Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(RepositorySettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
        }
        .padding([.top, .horizontal], 24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save", action: save)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
            .disabled(!canSave)
        }
        .padding([.horizontal, .bottom], 24)
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
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func remoteTab(_ draft: RepositorySettingsDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Remote table
            VStack(alignment: .leading, spacing: 8) {
                Text("Remote repository paths:")
                    .font(.system(size: 13))

                remoteTable
            }

            // Default remote picker
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Default remote")
                    .font(.system(size: 13))
                    .frame(width: 130, alignment: .leading)

                Picker("", selection: binding(\.selectedRemoteName)) {
                    ForEach(remoteOptions(for: draft), id: \.self) { remote in
                        Text(remote).tag(remote)
                    }
                }
                .pickerStyle(.menu)
                .disabled(remoteOptions(for: draft).isEmpty)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Default pull branch
            VStack(alignment: .leading, spacing: 8) {
                Text("Default pull branch")
                    .font(.system(size: 13))

                HStack(alignment: .center, spacing: 12) {
                    Picker("", selection: binding(\.selectedBranchMode)) {
                        Text("Detected branch").tag(SelectedBranchMode.detected)
                    }
                    .pickerStyle(.radioGroup)
                    .font(.system(size: 13))

                    Picker("", selection: binding(\.selectedDetectedBranch)) {
                        Text("Select a branch").tag("")
                        ForEach(branchOptions(for: draft), id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(draft.selectedBranchMode != .detected || branchOptions(for: draft).isEmpty)

                    Spacer()
                }

                HStack(alignment: .center, spacing: 12) {
                    Picker("", selection: binding(\.selectedBranchMode)) {
                        Text("Manual entry").tag(SelectedBranchMode.manual)
                    }
                    .pickerStyle(.radioGroup)
                    .font(.system(size: 13))

                    TextField("release/hotfix", text: binding(\.manualBranchName))
                        .textFieldStyle(.roundedBorder)
                        .disabled(draft.selectedBranchMode != .manual)

                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Spacer()

                Button("Open Remote URL") {
                    guard !draft.selectedRemoteName.isEmpty else { return }
                    onOpenRemoteURL(draft.selectedRemoteName)
                }
                .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
                .disabled(draft.selectedRemoteName.isEmpty)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            // Add / Edit / Remove buttons
            HStack(spacing: 8) {
            Button("Add") {
                remoteEditMode = .add
                showingRemoteEditSheet = true
            }
            .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))

            Button("Edit") {
                guard let url = remoteURLs[selectedRemoteName], !selectedRemoteName.isEmpty else { return }
                remoteEditMode = .edit(name: selectedRemoteName, url: url)
                showingRemoteEditSheet = true
            }
            .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
            .disabled(selectedRemoteName.isEmpty)

            Button("Remove") {
                Task {
                    await removeRemote(name: selectedRemoteName)
                }
            }
            .buttonStyle(GlassButtonStyle(tint: .red, fontSize: 11))
            .disabled(selectedRemoteName.isEmpty)

            Spacer()
        }
    }
    }

    private var pullFetchTab: some View {
        VStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Pull strategy")
                        .font(.system(size: 13))
                        .frame(width: 130, alignment: .trailing)

                    Picker("", selection: binding(\.pullStrategy)) {
                        Text("Merge").tag(PullStrategy.merge)
                        Text("Rebase").tag(PullStrategy.rebase)
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Auto fetch")
                        .font(.system(size: 13))
                        .frame(width: 240, alignment: .leading)

                    Picker("Auto fetch", selection: binding(\.autoFetchOverride)) {
                        Text(globalOptionTitle(value: appState.autoFetchEnabled))
                            .tag(Bool?.none)
                        Text("On").tag(Bool?.some(true))
                        Text("Off").tag(Bool?.some(false))
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Refresh when app becomes active")
                        .font(.system(size: 13))
                        .frame(width: 240, alignment: .leading)

                    Picker(
                        "Refresh when app becomes active",
                        selection: binding(\.refreshOnAppActiveOverride)
                    ) {
                        Text(globalOptionTitle(value: appState.refreshOnAppActive))
                            .tag(Bool?.none)
                        Text("On").tag(Bool?.some(true))
                        Text("Off").tag(Bool?.some(false))
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var advancedTab: some View {
        VStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Confirm detached HEAD checkout", isOn: binding(\.confirmDetachedHeadCheckout))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))

                Toggle("Skip protected branch commit warnings", isOn: binding(\.skipProtectedBranchCommitWarnings))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
                    .help("Skip local commit warnings for this repository. Remote branch protection still applies when pushing.")

                Toggle("Confirm destructive stash actions", isOn: binding(\.confirmDestructiveStashActions))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            userInformationSection

            providerAccountSection

            HStack(spacing: 8) {
                Spacer()

                Button("Open .gitignore", action: onOpenGitIgnore)
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))

                Button("Open .git/config", action: onOpenGitConfig)
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gitFlowTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable Git Flow", isOn: $gitFlowConfiguration.isEnabled)
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 12) {
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

            VStack(alignment: .leading, spacing: 10) {
                Text("Branch prefixes")
                    .font(.headline)

                prefixField("Feature", text: $gitFlowConfiguration.featurePrefix)
                prefixField("Bugfix", text: $gitFlowConfiguration.bugfixPrefix)
                prefixField("Release", text: $gitFlowConfiguration.releasePrefix)
                prefixField("Hotfix", text: $gitFlowConfiguration.hotfixPrefix)
            }
            .disabled(!gitFlowConfiguration.isEnabled)

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Start new flows in") {
                    Picker("Start new flows in", selection: $gitFlowConfiguration.defaultStartDestination) {
                        ForEach(GitFlowStartDestination.allCases) { destination in
                            Text(destination.displayName).tag(destination)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                    .accessibilityLabel("Default Git Flow start destination")
                    .accessibilityValue(gitFlowConfiguration.defaultStartDestination.displayName)
                }

                Text("This is the default. You can change the destination for each flow from the Start sheet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(!gitFlowConfiguration.isEnabled)

            VStack(alignment: .leading, spacing: 10) {
                Text("Finish behavior")
                    .font(.headline)

                LabeledContent("Feature & Bugfix") {
                    Picker("Feature & Bugfix", selection: $gitFlowConfiguration.topicFinishStrategy) {
                        ForEach(GitFlowTopicFinishStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                    .accessibilityLabel("Default Feature and Bugfix finish strategy")
                    .accessibilityValue(gitFlowConfiguration.topicFinishStrategy.displayName)
                }

                Toggle(
                    "Create an annotated tag when finishing Release",
                    isOn: $gitFlowConfiguration.createReleaseTagOnFinish
                )
                .toggleStyle(.checkbox)
                Toggle(
                    "Create an annotated tag when finishing Hotfix",
                    isOn: $gitFlowConfiguration.createHotfixTagOnFinish
                )
                .toggleStyle(.checkbox)

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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func branchPicker(
        title: String,
        selection: Binding<String>,
        showsCreateDevelopBranchButton: Bool = false
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Picker(title, selection: selection) {
                    Text("Select a branch").tag("")
                    ForEach(branches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180)

                if showsCreateDevelopBranchButton {
                    Button("Create New…") {
                        showingCreateDevelopBranchSheet = true
                    }
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
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
            TextField("\(title.lowercased())/", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("User information")
                .font(.system(size: 16, weight: .medium))

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Use global user settings", isOn: binding(\.useGlobalUserSettings))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Full Name:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Full Name", text: binding(\.userName))
                        .textFieldStyle(.roundedBorder)
                        .disabled(draft?.useGlobalUserSettings == true)
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Email address:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Email address", text: binding(\.userEmail))
                        .textFieldStyle(.roundedBorder)
                        .disabled(draft?.useGlobalUserSettings == true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var providerAccountSection: some View {
        let options = providerRemoteAccountOptions
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Git provider accounts")
                    .font(.headline)

                Text("Choose which connected account this remote uses. Automatic uses the only matching account and asks before a remote operation when more than one account matches.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(options) { option in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.remoteName)
                                .font(.subheadline)
                            Text(option.identity.canonicalHTTPSURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(minWidth: 140, idealWidth: 190, maxWidth: 240, alignment: .leading)

                        Picker("Account for \(option.remoteName)", selection: providerAccountSelectionBinding(for: option)) {
                            Text("Automatic").tag("")
                            ForEach(option.accounts) { account in
                                Text(accountDisplayName(account)).tag(account.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
