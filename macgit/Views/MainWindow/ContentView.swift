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
import GoogleSignIn

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var appUpdateController: AppUpdateController
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @EnvironmentObject private var repositoryBookmarkController: RepositoryBookmarkController
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject var aiProviderController: AIProviderController
    let isWelcomeWindow: Bool
    let initialShowsHistory: Bool?

    @State private var showingAppSettings = false
    @State private var selectedAppSettingsSection: AppSettingsSection = .general

    @State private var repositoryOpenError = ""
    @State private var showingRepositoryOpenError = false
    @State private var externalOpenTask: Task<Void, Never>?
    @State private var repositoryURL: URL?
    @State private var showingRepoPickerSheet = false
    @State private var showingCloneSheet = false
    @State private var showingKeepCurrentAlert = false
    @State private var pendingAction: FileMenuAction?
    @State private var shouldFitScreenWhenRepositoryOpens = false
    @State private var webOpeningProgressID: UUID?
    @State private var windowContext = RepositoryWindowContext()
    @StateObject private var operationProgress = RepositoryOperationProgress()

    init(
        request: RepositoryWindowRequest?,
        isWelcomeWindow: Bool = false,
        accountController: AccountSessionController,
        providerAccountController: GitProviderAccountController,
        aiProviderController: AIProviderController
    ) {
        self.initialShowsHistory = request?.showsHistory
        self.isWelcomeWindow = isWelcomeWindow
        self.accountController = accountController
        self.providerAccountController = providerAccountController
        self.aiProviderController = aiProviderController
        _repositoryURL = State(initialValue: request?.repositoryURL)
        _showingCloneSheet = State(
            initialValue: request?.initialPresentation == .cloneRepository
        )
        _shouldFitScreenWhenRepositoryOpens = State(
            initialValue: request?.shouldFitVisibleScreen == true
        )
    }

    var body: some View {
        Group {
            if isWelcomeWindow {
                WelcomeView(accountDisplayName: accountController.account?.displayLabel, onRepositoryOpened: { url in
                    openRepository(url, inNewWindow: true)
                })
            } else if let url = repositoryURL {
                MainWindowView(
                    repositoryURL: url,
                    initialShowsHistory: initialShowsHistory,
                    providerAccountController: providerAccountController,
                    aiProviderController: aiProviderController,
                    onOpenConnections: accountController.presentConnections,
                    windowContext: windowContext,
                    operationProgress: operationProgress
                )
                .environmentObject(accountController)
                .background(
                    WindowInitialScreenFitModifier(
                        isEnabled: shouldFitScreenWhenRepositoryOpens
                    )
                )
            } else {
                RepoPickerView(
                    showCloneSheetInitially: false,
                    onRepositoryOpened: { url in
                        openRepository(url, inNewWindow: false)
                    }
                )
            }
        }
        .onOpenURL(perform: handleExternalURL)
        .alert("Cannot Open Repository", isPresented: $showingRepositoryOpenError) {
        } message: {
            Text(repositoryOpenError)
        }
        .overlay {
            if repositoryURL == nil, let operation = webOpeningOperation {
                RepositoryOperationOverlayView(operation: operation, onCancel: {})
            }
        }
        .onChange(of: accountController.isOpeningAccountOnWeb, initial: true) { _, isOpening in
            if isOpening, webOpeningProgressID == nil {
                webOpeningProgressID = operationProgress.begin(
                    message: "Opening Commit+ on the web...",
                    canCancel: false
                )
            } else if !isOpening, let id = webOpeningProgressID {
                operationProgress.end(id)
                webOpeningProgressID = nil
            }
        }
        .replacingSheet(isPresented: $showingRepoPickerSheet) {
            RepoPickerView(
                showCloneSheetInitially: false,
                onRepositoryOpened: { url in
                    openRepository(url, inNewWindow: false)
                }
            )
            .frame(minWidth: 560, minHeight: 480)
        }
        .replacingSheet(isPresented: $showingCloneSheet) {
            CloneSheetView(onClone: { url in
                showingCloneSheet = false
                openRepository(url, inNewWindow: repositoryURL != nil)
            })
        }
        .replacingSheet(item: accountSheetPresentation) { sheet in
            Group {
                switch sheet {
                case .authentication(let mode):
                    AuthenticationSheet(controller: accountController, mode: mode)
                case .manageAccount:
                    ManageAccountSheet(
                        controller: accountController
                    )
                case .connections:
                    ConnectionsSheet(
                        accountController: accountController,
                        providerAccountController: providerAccountController
                    )
                case .settingsConflict:
                    SettingsSyncConflictSheet(controller: accountController)
                case .deviceLimit:
                    DeviceLimitSheet(controller: accountController)
                }
            }
            .disabled(accountController.isOpeningAccountOnWeb)
            .overlay {
                if let operation = webOpeningOperation {
                    RepositoryOperationOverlayView(operation: operation, onCancel: {})
                }
            }
            .interactiveDismissDisabled(accountController.isOpeningAccountOnWeb)
        }
        .replacingSheet(isPresented: $showingAppSettings) {
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
        .alert("Current Repository is Open", isPresented: $showingKeepCurrentAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Close Current", role: .destructive) {
                closeCurrentAndPerformPending()
            }
            Button("Keep Open") {
                openNewWindowForPending()
            }
        } message: {
            Text("Do you want to keep the current repository open?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .fileMenuAction)) { notification in
            guard windowContext.owns(notification),
                  let action = notification.userInfo?["action"] as? FileMenuAction else { return }
            handleFileMenuAction(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAppSettings)) { notification in
            if let targetWindow = notification.object as? NSWindow {
                guard targetWindow === windowContext.window else { return }
            } else if windowContext.window !== NSApp.keyWindow {
                return
            }
            if let rawSection = notification.userInfo?["section"] as? String,
               let section = AppSettingsSection(rawValue: rawSection) {
                selectedAppSettingsSection = section
            } else {
                selectedAppSettingsSection = .general
            }
            showingAppSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newRepositoryTab)) { notification in
            guard !isWelcomeWindow, windowContext.owns(notification) else { return }
            openWindow(
                id: "main",
                value: RepositoryWindowRequest.repositoryPicker()
            )
        }
        .task(id: accountController.account?.uid) {
            await providerAccountController.updateMacgitAccount(accountController.account)
            await repositoryBookmarkController.updateAccount(accountController.account)
        }
        .background(
            RepositoryWindowReader(
                repositoryWindowContext: windowContext,
                title: isWelcomeWindow ? "Welcome to Commit+" : (repositoryURL?.lastPathComponent ?? "Choose a Repository"),
                repositoryURL: repositoryURL,
                allowsTabbing: !isWelcomeWindow
            )
        )
        .focusedSceneValue(
            \.repositoryWindowCommandState,
            RepositoryWindowCommandState(
                hasOpenRepository: repositoryURL != nil,
                hasActiveOperation: operationProgress.activeOperation != nil,
                allowsTabs: !isWelcomeWindow
            )
        )
        // Prefer the scene that opened browser sign-in. If it was closed (or the
        // app relaunched), allow another existing scene to receive the callback.
        .handlesExternalEvents(
            preferring: preferredExternalEvents,
            allowing: ["macgit://session", "macgit://open-repository"]
        )
        .windowDismissBehavior(
            operationProgress.activeOperation == nil ? .automatic : .disabled
        )
        .modifier(CommandLineSetupTipModifier(
            isBlocked: showingAppSettings || showingCloneSheet || showingRepoPickerSheet
                || showingKeepCurrentAlert || accountController.presentedSheet != nil
                || operationProgress.activeOperation != nil
        ))
        .sheetPresentationScope()
    }

    private var accountSheetPresentation: Binding<AccountSheet?> {
        Binding(
            get: {
                guard let window = windowContext.window,
                      accountController.sheetPresentationWindow === window else { return nil }
                return accountController.presentedSheet
            },
            set: { sheet in
                guard let window = windowContext.window,
                      accountController.sheetPresentationWindow === window else { return }
                accountController.presentedSheet = sheet
            }
        )
    }

    private var preferredExternalEvents: Set<String> {
        var events: Set<String> = repositoryURL == nil ? ["macgit://open-repository"] : []
        if accountController.webSignInWindowNumber != nil,
           accountController.webSignInWindowNumber == windowContext.window?.windowNumber {
            events.insert("macgit://session")
        }
        return events
    }

    private func handleExternalURL(_ url: URL) {
        guard RepositoryOpenRequest.recognizes(url) else {
            Task { @MainActor in
                if await accountController.handleWebSignInCallback(url) { return }
                if await providerAccountController.handleProviderOAuthCallback(url) { return }
                _ = GIDSignIn.sharedInstance.handle(url)
            }
            return
        }
        // Serialize requests delivered to this scene, including repeated commands during launch.
        let previousTask = externalOpenTask
        externalOpenTask = Task { @MainActor in
            await previousTask?.value
            do {
                let directory = try RepositoryOpenRequest.repositoryURL(from: url)
                let root = try await RepositoryPathResolver().root(at: directory)
                if RepositoryWindowContext.focusRepository(at: root) { return }
                if repositoryURL?.resolvingSymlinksInPath().standardizedFileURL == root { return }
                guard RepositoryWindowContext.reserveOpening(root) else { return }
                RecentRepositoriesStore.shared.add(root)
                openRepository(root, inNewWindow: repositoryURL != nil)
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                repositoryOpenError = error.localizedDescription
                showingRepositoryOpenError = true
            }
        }
    }

    private var webOpeningOperation: RepositoryOperationProgressItem? {
        guard let operation = operationProgress.activeOperation,
              operation.id == webOpeningProgressID else { return nil }
        return operation
    }

    private func handleFileMenuAction(_ action: FileMenuAction) {
        switch action {
        case .cloneRepository:
            showingCloneSheet = true
        case .openRepository, .openRecent:
            if repositoryURL != nil {
                pendingAction = action
                showingKeepCurrentAlert = true
            } else {
                performAction(action, inNewWindow: false)
            }
        case .closeRepository:
            repositoryURL = nil
            showingRepoPickerSheet = false
            showingCloneSheet = false
        }
    }

    private func performAction(_ action: FileMenuAction, inNewWindow: Bool) {
        switch action {
        case .cloneRepository:
            if inNewWindow {
                openWindow(
                    id: "main",
                    value: RepositoryWindowRequest.cloneRepository()
                )
            } else {
                showingCloneSheet = true
            }
        case .openRepository:
            if inNewWindow {
                openWindow(
                    id: "main",
                    value: RepositoryWindowRequest.repositoryPicker()
                )
            } else {
                showingRepoPickerSheet = true
            }
        case .openRecent(let url):
            openRepository(url, inNewWindow: inNewWindow)
        case .closeRepository:
            repositoryURL = nil
        }
    }

    private func closeCurrentAndPerformPending() {
        repositoryURL = nil
        if let action = pendingAction {
            performAction(action, inNewWindow: false)
            pendingAction = nil
        }
    }

    private func openNewWindowForPending() {
        if let action = pendingAction {
            performAction(action, inNewWindow: true)
            pendingAction = nil
        }
    }

    private func openRepository(_ url: URL, inNewWindow: Bool) {
        showingRepoPickerSheet = false
        showingCloneSheet = false
        if isWelcomeWindow || inNewWindow {
            openWindow(
                id: "main",
                value: RepositoryWindowRequest.repository(
                    url,
                    shouldFitVisibleScreen: true
                )
            )
        } else {
            shouldFitScreenWhenRepositoryOpens = true
            repositoryURL = url
        }
    }
}
