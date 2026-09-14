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
import GoogleSignIn
import SwiftUI

@main
struct macgitApp: App {
    @NSApplicationDelegateAdaptor(MacgitApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appState: AppState
    @StateObject private var appUpdateController = AppUpdateController(updater: SparkleAppUpdater())
    @StateObject private var accountController: AccountSessionController
    @StateObject private var providerAccountController: GitProviderAccountController
    @StateObject private var aiProviderController: AIProviderController
    @StateObject private var featureAccessController: FeatureAccessController
    @StateObject private var repositoryVisibilityController: RepositoryVisibilityController
    @StateObject private var repositoryBookmarkController: RepositoryBookmarkController
    @StateObject private var gitFlowConfigurationSyncController: GitFlowConfigurationSyncController
    @State private var showingAppSettings = false
    @State private var selectedAppSettingsSection: AppSettingsSection = .general
    @FocusedValue(\.repositoryWindowCommandState) private var repositoryWindowCommandState

    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
        let firebaseStatus = FirebaseBootstrap.configure()
        let appState = AppState.shared
        _appState = StateObject(wrappedValue: appState)
        let accountController = AccountSessionController(
            auth: FirebaseAuthService(),
            bootstrapStatus: firebaseStatus,
            entitlementProvider: firebaseStatus == .configured
                ? FirestoreEntitlementStore()
                : nil,
            entitlementCache: UserDefaultsEntitlementCache(),
            webAccountSessionProvider: firebaseStatus == .configured
                ? FirebaseWebAccountSessionService()
                : nil,
            openWebURL: NSWorkspace.shared.open,
            appState: appState,
            settingsStore: firebaseStatus == .configured
                ? FirestoreSettingsStore()
                : nil,
            deviceIdentity: firebaseStatus == .configured
                ? CommitPlusDeviceIdentityProvider()
                : nil,
            deviceAccessProvider: firebaseStatus == .configured
                ? FirestoreDeviceAccessService()
                : nil,
            deviceSessionCache: UserDefaultsAccountDeviceSessionCache()
        )
        _accountController = StateObject(wrappedValue: accountController)
        let featureAccessController = FeatureAccessController(
            provider: firebaseStatus == .configured
                ? FirestoreFeaturePolicyStore()
                : nil,
            cache: UserDefaultsFeaturePolicyCache()
        )
        _featureAccessController = StateObject(wrappedValue: featureAccessController)
        let providerConfiguration = GitHubProviderAuthConfiguration.appConfiguration()
        let gitLabProviderConfiguration = GitLabProviderAuthConfiguration.appConfiguration()
        let providerCloudStore: GitProviderAccountCloudStore? = firebaseStatus == .configured
            ? FirestoreGitProviderAccountStore()
            : nil
        let providerStore = LocalFirstGitProviderAccountStore(cloudStore: providerCloudStore)
        let providerTokenVault = KeychainGitProviderTokenVault()
        _providerAccountController = StateObject(
            wrappedValue: GitProviderAccountController(
                store: providerStore,
                tokenVault: providerTokenVault,
                authService: GitHubProviderAuthService(configuration: providerConfiguration),
                configuration: providerConfiguration,
                gitLabAuthService: GitLabProviderAuthService(configuration: gitLabProviderConfiguration),
                gitLabRedirectURI: gitLabProviderConfiguration.redirectURI,
                openURL: NSWorkspace.shared.open,
                multipleAccountAccess: {
                    featureAccessController.decision(
                        for: .multipleProviderAccounts,
                        entitlement: accountController.entitlement
                    )
                }
            )
        )
        let managedUsage = CommitPlusAIUsageController()
        managedUsage.setSession(uid: accountController.account?.uid)
        let managedTokens = FirebaseCommitPlusAITokenProvider()
        let managedClient = CommitPlusAIClient(baseURL: CommitPlusAIClient.configuredURL(), tokens: managedTokens) { [weak managedUsage] allowance, identity in
            guard managedTokens.currentSession() == identity else { return }
            managedUsage?.accept(allowance, uid: identity.uid)
        }
        managedUsage.loader = { try await managedClient.allowance() }
        let managedAccess: @MainActor @Sendable () -> Bool = {
            CommitPlusAISelectionPolicy.canSelect(isSignedIn: accountController.account != nil,
                                                 hasProAccess: accountController.entitlement.hasProAccess)
        }
        let managedProvider = CommitPlusAIProvider(client: managedClient, usage: managedUsage, canAccess: managedAccess)
        _aiProviderController = StateObject(wrappedValue: AIProviderController(
            restrictedProviderAccess: {
                featureAccessController.decision(
                    for: .aiBringYourOwnKey,
                    entitlement: accountController.account == nil ? .free : accountController.entitlement
                )
            },
            managedProviderAccess: managedAccess,
            managedProvider: managedProvider,
            managedUsageController: managedUsage
        ))
        _repositoryVisibilityController = StateObject(
            wrappedValue: RepositoryVisibilityController(
                services: [
                    .github: GitHubRepositoryVisibilityService(),
                    .gitlab: GitLabRepositoryVisibilityService(),
                ],
                tokenVault: providerTokenVault,
                cache: UserDefaultsRepositoryVisibilityCache()
            )
        )
        _repositoryBookmarkController = StateObject(
            wrappedValue: RepositoryBookmarkController(
                cloudStore: firebaseStatus == .configured
                    ? FirestoreRepositoryBookmarkStore()
                    : nil
            )
        )
        _gitFlowConfigurationSyncController = StateObject(
            wrappedValue: GitFlowConfigurationSyncController(
                cloudStore: firebaseStatus == .configured
                    ? FirestoreGitFlowConfigurationStore()
                    : nil
            )
        )
    }

    private func performUndoMenuAction(_ action: GitUndoMenuAction) {
        guard let commandContext = ConflictUndoCommandContext.identifier(for: NSApp.keyWindow) else {
            WindowScopedNotification.post(
                name: .gitUndoAction,
                userInfo: ["action": action]
            )
            return
        }

        if performTextUndoIfAvailable(action, in: NSApp.keyWindow) {
            return
        }

        NotificationCenter.default.post(
            name: .conflictUndoAction,
            object: nil,
            userInfo: [
                "action": action,
                "commandContext": commandContext,
            ]
        )
    }

    private var hasOpenRepository: Bool {
        repositoryWindowCommandState?.hasOpenRepository == true
    }

    private func performToolbarAction(_ action: ToolbarAction) {
        WindowScopedNotification.post(
            name: .toolbarAction,
            userInfo: ["action": action]
        )
    }

    private func openWebPage(_ urlProvider: () throws -> URL) {
        guard let url = try? urlProvider() else { return }
        NSWorkspace.shared.open(url)
    }

    private func performTextUndoIfAvailable(
        _ action: GitUndoMenuAction,
        in window: NSWindow?
    ) -> Bool {
        guard let textView = window?.firstResponder as? NSTextView,
              let undoManager = textView.undoManager else {
            return false
        }

        switch action {
        case .undo where undoManager.canUndo:
            undoManager.undo()
            return true
        case .redo where undoManager.canRedo:
            undoManager.redo()
            return true
        default:
            return false
        }
    }

    private func windowContent(
        request: RepositoryWindowRequest?,
        isWelcomeWindow: Bool = false
    ) -> some View {
        ContentView(
            request: request,
            isWelcomeWindow: isWelcomeWindow,
            accountController: accountController,
            providerAccountController: providerAccountController,
            aiProviderController: aiProviderController,
            isShowingAppSettings: showingAppSettings
        )
            .environmentObject(appState)
            .environmentObject(appUpdateController)
            .environmentObject(featureAccessController)
            .environmentObject(repositoryVisibilityController)
            .environmentObject(repositoryBookmarkController)
            .environmentObject(gitFlowConfigurationSyncController)
            .preferredColorScheme(appState.appearance.colorScheme)
            .task {
                appUpdateController.start()
            }
            .onChange(of: accountController.account?.uid, initial: true) { _, uid in
                aiProviderController.managedUsageController?.setSession(uid: uid)
                Task { await aiProviderController.refreshAvailability() }
            }
            .onChange(of: accountController.entitlement) { _, _ in
                Task { await aiProviderController.refreshAvailability() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task {
                    await aiProviderController.managedUsageController?.refresh(force: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAppSettings)) { notification in
                if let rawSection = notification.userInfo?["section"] as? String,
                   let section = AppSettingsSection(rawValue: rawSection) {
                    selectedAppSettingsSection = section
                } else {
                    selectedAppSettingsSection = .general
                }
                showingAppSettings = true
            }
            .sheet(isPresented: $showingAppSettings) {
                AppSettingsView(
                    appState: appState,
                    accountController: accountController,
                    featureAccessController: featureAccessController,
                    providerAccountController: providerAccountController,
                    aiProviderController: aiProviderController,
                    appUpdateController: appUpdateController,
                    isPresented: $showingAppSettings,
                    selectedSection: $selectedAppSettingsSection
                )
                    .environmentObject(featureAccessController)
                    .preferredColorScheme(appState.appearance.colorScheme)
            }
    }

    var body: some Scene {
        Window("Welcome to Commit+", id: "welcome") {
            windowContent(request: nil, isWelcomeWindow: true)
        }
        .defaultSize(width: 1180, height: 780)
        .defaultLaunchBehavior(.presented)

        WindowGroup(id: "main", for: RepositoryWindowRequest.self) { request in
            windowContent(request: request.wrappedValue)
        }
        .defaultSize(width: 860, height: 680)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            RepositoryFileCommands()

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdateController.checkForUpdates()
                }

                Button("Settings...") {
                    selectedAppSettingsSection = .general
                    showingAppSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo Git Action") {
                    performUndoMenuAction(.undo)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo Git Action") {
                    performUndoMenuAction(.redo)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Actions") {
                Button("Commit...") {
                    performToolbarAction(.commit)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Pull") {
                    performToolbarAction(.pull)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Push") {
                    performToolbarAction(.push)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("Fetch") {
                    performToolbarAction(.fetch)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("Add Submodule...") {
                    performToolbarAction(.addSubmodule)
                }
                .disabled(!hasOpenRepository)

                Button("Add/Link Subtree...") {
                    performToolbarAction(.addLinkSubtree)
                }
                .disabled(!hasOpenRepository)

                Divider()

                Button("Branch...") {
                    performToolbarAction(.branch)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Merge...") {
                    performToolbarAction(.merge)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Stash...") {
                    performToolbarAction(.stash)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Remote") {
                    performToolbarAction(.remote)
                }
                .disabled(!hasOpenRepository)

                Button("Show in Finder") {
                    performToolbarAction(.finder)
                }
                .disabled(!hasOpenRepository)

                Button("Open in External Editor") {
                    performToolbarAction(.editor)
                }
                .disabled(!hasOpenRepository)

                Button("Open in Terminal") {
                    performToolbarAction(.terminal)
                }
                .disabled(!hasOpenRepository)

                Button("Repository Settings...") {
                    performToolbarAction(.repositorySettings)
                }
                .disabled(!hasOpenRepository)

                Divider()

                Button("Search...") {
                    WindowScopedNotification.post(name: .showSearchModal)
                }
                .disabled(!hasOpenRepository)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            GitFlowCommands()

            CommandMenu("Accounts") {
                AccountMenuContent(controller: accountController)
            }

            HeaderButtonsCommands(appState: appState)

            CommandGroup(replacing: .help) {
                Button("Commit+ Documentation") {
                    openWebPage {
                        try CommitPlusWebConfiguration.documentationURL()
                    }
                }

                Divider()

                Button("Contact Support") {
                    openWebPage {
                        try CommitPlusWebConfiguration.contactURL()
                    }
                }

                Button("Report an Issue…") {
                    openWebPage {
                        try CommitPlusWebConfiguration.reportIssueURL()
                    }
                }
            }

            CommandGroup(before: .toolbar) {
                Toggle(isOn: $appState.showToolbarButtonText) {
                    Label("Show Button Text", systemImage: "character.textbox")
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                Toggle(isOn: $appState.showGitFlow) {
                    Label("Show Git Flow", systemImage: "point.3.connected.trianglepath.dotted")
                }
                Toggle(isOn: $appState.showSubmodules) {
                    Label("Show Submodules", systemImage: "folder.badge.gearshape")
                }
                Toggle(isOn: $appState.showSubtrees) {
                    Label("Show Subtrees", systemImage: "tree")
                }
            }
        }
    }
}
