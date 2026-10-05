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
    @StateObject private var customActionStore: CustomActionStore
    @StateObject private var gitFlowConfigurationSyncController: GitFlowConfigurationSyncController
    @StateObject private var cloudLifecycleController: AppCloudLifecycleController
    @State private var selectedAppSettingsSection: AppSettingsSection = .general
    private let repositoryWindowLifecycleController = RepositoryWindowLifecycleController()
    @FocusedValue(\.repositoryWindowCommandState) private var repositoryWindowCommandState
    @FocusedValue(\.customActionCommandState) private var customActionCommandState

    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
        let firebaseStatus = FirebaseBootstrap.configure()
        // Unit-test hosts must not open Firestore: the shared LevelDB cache
        // aborts when several test hosts (or a running app) use it at once.
        let cloudFeaturesEnabled = firebaseStatus == .configured && !FirebaseBootstrap.isRunningUnitTests
        let appState = AppState.shared
        _appState = StateObject(wrappedValue: appState)
        let accountController = AccountSessionController(
            auth: FirebaseAuthService(),
            bootstrapStatus: firebaseStatus,
            entitlementProvider: cloudFeaturesEnabled
                ? FirestoreEntitlementStore()
                : nil,
            entitlementCache: UserDefaultsEntitlementCache(),
            webAccountSessionProvider: cloudFeaturesEnabled
                ? FirebaseWebAccountSessionService()
                : nil,
            openWebURL: NSWorkspace.shared.open,
            appState: appState,
            settingsStore: cloudFeaturesEnabled
                ? FirestoreSettingsStore()
                : nil,
            deviceIdentity: cloudFeaturesEnabled
                ? CommitPlusDeviceIdentityProvider()
                : nil,
            deviceAccessProvider: cloudFeaturesEnabled
                ? FirestoreDeviceAccessService()
                : nil,
            deviceSessionCache: UserDefaultsAccountDeviceSessionCache()
        )
        _accountController = StateObject(wrappedValue: accountController)
        let featureAccessController = FeatureAccessController(
            provider: cloudFeaturesEnabled
                ? FirestoreFeaturePolicyStore()
                : nil,
            cache: UserDefaultsFeaturePolicyCache()
        )
        _featureAccessController = StateObject(wrappedValue: featureAccessController)
        let providerConfiguration = GitHubProviderAuthConfiguration.appConfiguration()
        let gitLabProviderConfiguration = GitLabProviderAuthConfiguration.appConfiguration()
        let providerCloudStore: GitProviderAccountCloudStore? = cloudFeaturesEnabled
            ? FirestoreGitProviderAccountStore()
            : nil
        let providerStore = LocalFirstGitProviderAccountStore(cloudStore: providerCloudStore)
        let providerTokenVault = KeychainGitProviderTokenVault()
        let providerAccountController = GitProviderAccountController(
            store: providerStore,
            tokenVault: providerTokenVault,
            authService: GitHubProviderAuthService(configuration: providerConfiguration),
            configuration: providerConfiguration,
            gitLabAuthService: GitLabProviderAuthService(configuration: gitLabProviderConfiguration),
            gitLabRedirectURI: gitLabProviderConfiguration.redirectURI,
            openURL: NSWorkspace.shared.open,
            hasProAccess: { accountController.entitlement.hasProAccess },
            multipleAccountAccess: {
                featureAccessController.decision(
                    for: .multipleProviderAccounts,
                    entitlement: accountController.entitlement
                )
            }
        )
        _providerAccountController = StateObject(wrappedValue: providerAccountController)
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
                cache: SQLiteRepositoryVisibilityCache()
            )
        )
        let repositoryBookmarkController = RepositoryBookmarkController(
            cloudStore: cloudFeaturesEnabled
                ? FirestoreRepositoryBookmarkStore()
                : nil
        )
        _repositoryBookmarkController = StateObject(wrappedValue: repositoryBookmarkController)
        let customActionStore = CustomActionStore(
            cloudStore: cloudFeaturesEnabled ? FirestoreCustomActionStore() : nil
        )
        customActionStore.observeSession(accountController: accountController, appState: appState)
        _customActionStore = StateObject(wrappedValue: customActionStore)
        _gitFlowConfigurationSyncController = StateObject(
            wrappedValue: GitFlowConfigurationSyncController(
                cloudStore: cloudFeaturesEnabled
                    ? FirestoreGitFlowConfigurationStore()
                    : nil
            )
        )
        _cloudLifecycleController = StateObject(
            wrappedValue: AppCloudLifecycleController(
                startFeaturePolicy: featureAccessController.start,
                synchronizeAccount: { account in
                    async let providerAccounts: Void = providerAccountController.updateMacgitAccount(account)
                    async let bookmarks: Void = repositoryBookmarkController.updateAccount(account)
                    _ = await (providerAccounts, bookmarks)
                }
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
        TermsAcceptanceGate {
        LocalDataLoadingView {
            ContentView(
                request: request,
                isWelcomeWindow: isWelcomeWindow,
                accountController: accountController,
                providerAccountController: providerAccountController,
                aiProviderController: aiProviderController,
                selectedAppSettingsSection: $selectedAppSettingsSection,
                repositoryWindowLifecycleController: repositoryWindowLifecycleController
            )
                .environmentObject(appState)
                .environmentObject(appUpdateController)
                .environmentObject(featureAccessController)
                .environmentObject(repositoryVisibilityController)
                .environmentObject(repositoryBookmarkController)
                .environmentObject(customActionStore)
                .environmentObject(gitFlowConfigurationSyncController)
                .preferredColorScheme(appState.appearance.colorScheme)
                .font(appState.textSize.font)
                .environment(\.appTextScale, appState.textSize.scale)
                .task {
                    appUpdateController.start()
                }
                .task(id: accountController.account?.uid) {
                    cloudLifecycleController.start()
                    await cloudLifecycleController.updateAccount(accountController.account)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    Task { await customActionStore.syncNow() }
                }
                .onChange(of: accountController.account?.uid, initial: true) { _, uid in
                    aiProviderController.managedUsageController?.setSession(uid: uid)
                }
                .onChange(of: accountController.account?.uid) { _, _ in
                    aiProviderController.invalidateAvailability()
                }
                .onChange(of: accountController.entitlement) { _, _ in
                    providerAccountController.refreshConnectionAccess()
                    aiProviderController.invalidateAvailability()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task {
                        await aiProviderController.refreshManagedUsageIfNeeded()
                    }
                }
        }
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
        .defaultSize(width: 1180, height: 780)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            RepositoryFileCommands()

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdateController.checkForUpdates()
                }

                Button("Settings...") {
                    WindowScopedNotification.post(
                        name: .showAppSettings,
                        userInfo: ["section": AppSettingsSection.general.rawValue]
                    )
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

                Menu("Custom Actions") {
                    if let state = customActionCommandState {
                        CustomActionMenuContent(
                            store: customActionStore,
                            surface: state.surface,
                            context: state.context,
                            hasActiveOperation: state.hasActiveOperation,
                            includesRepositoryActions: true,
                            onRun: { id, surface in
                                WindowScopedNotification.post(
                                    name: .customActionMenuAction,
                                    userInfo: ["id": id, "surface": surface]
                                )
                            }
                        )
                    } else {
                        Text("No Repository Open")
                        Divider()
                        CustomActionAddMenuButton()
                    }
                }

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

        Window("Settings", id: "settings") {
            AppSettingsView(
                appState: appState,
                accountController: accountController,
                featureAccessController: featureAccessController,
                providerAccountController: providerAccountController,
                aiProviderController: aiProviderController,
                appUpdateController: appUpdateController,
                customActionStore: customActionStore,
                selectedSection: $selectedAppSettingsSection
            )
            .environmentObject(featureAccessController)
            .preferredColorScheme(appState.appearance.colorScheme)
            .font(appState.textSize.font)
            .environment(\.appTextScale, appState.textSize.scale)
        }
        .defaultSize(width: 920, height: 640)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }

}
