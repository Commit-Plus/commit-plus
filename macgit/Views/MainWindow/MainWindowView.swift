//
//  MainWindowView.swift
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

struct WindowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    func repositoryScreenVisibility(isActive: Bool) -> some View {
        opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

struct PendingCommitDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let commits: [GitDraggedCommit]
    let targetBranch: String
}

struct PendingBranchDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let sourceBranch: String
    let targetBranch: String
    var operation: GitDragBranchOperation
}

struct PendingPushBranchDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let branch: String
    let remote: String

    var remoteBranch: String {
        "\(remote)/\(branch)"
    }
}

struct PendingTagMoveConfirmation: Identifiable, Equatable {
    let id = UUID()
    let tagName: String
    let currentCommit: GitTagDetails
    let newCommit: GitDraggedCommit
    let remotes: [String]
}

struct PendingForcePushTagConfirmation: Identifiable, Equatable {
    let id = UUID()
    let tag: String
    let remote: String
}

struct PendingTagDeletion: Identifiable, Equatable {
    let id = UUID()
    let tag: String
    let remotes: [String]
}

struct PendingSubtreeOperation: Identifiable, Equatable {
    let operation: SubtreeOperation
    let entry: GitSubtreeEntry

    var id: String {
        "\(operation)-\(entry.id)"
    }
}

struct TagStartPoint: Equatable {
    let hash: String
    let message: String
    var isBranch = false

    var shortHash: String {
        String(hash.prefix(7))
    }
}

struct MainWindowView: View {
    private static let pinnedToolbarShortcutsMinimumWindowWidth: CGFloat = 1200

    let repositoryURL: URL
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject var aiProviderController: AIProviderController
    let onOpenConnections: () -> Void
    let windowContext: RepositoryWindowContext
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var accountController: AccountSessionController
    @EnvironmentObject var featureAccessController: FeatureAccessController
    @EnvironmentObject var repositoryVisibilityController: RepositoryVisibilityController
    @EnvironmentObject var gitFlowConfigurationSyncController: GitFlowConfigurationSyncController
    @EnvironmentObject var customActionStore: CustomActionStore
    @Environment(\.openWindow) private var openWindow
    let repoSettingsStore = RepoSettingsStore.shared
    let gitFlowConfigurationStore = GitFlowConfigurationStore()
    let providerAccountPreferenceStore = GitProviderAccountPreferenceStore.shared
    private let fileService = RepositorySettingsFileService()
    let undoExecutor = GitUndoExecutor()
    let initialShowsHistory: Bool?
    @State var selectedItem: SidebarSelection? = .item(.fileStatus)
    @State private var windowWidth: CGFloat = 0
    @State private var appActivationSyncTask: Task<Void, Never>?
    private static let appActivationSyncDebounce: Duration = .milliseconds(1500)
    @State var showingCommitSheet = false
    @State var showingPullSheet = false
    @State var showingPushSheet = false
    @State var pushSheetSelection: (branch: String, remote: String, remoteBranch: String)?
    @State var pendingBranchForcePush: RepositorySheetRequest<(branch: String, remote: String?, remoteBranch: String?)>?
    @State var pendingSheetForcePush: (branch: String, remote: String, remoteBranch: String)?
    @State var showingFetchSheet = false
    @State var showingAddSubmoduleSheet = false
    @State var showingAddLinkSubtreeSheet = false
    @State var branchSheetPresentation: BranchSheetPresentation?
    @State var showingTagSheet = false
    @State var showingNewTagSheet = false
    @State var tagNameInput = ""
    @State var tagStartPoint: TagStartPoint?
    @State var showingMergeSheet = false
    @State var showingStashSheet = false
    @State var showingCheckoutConfirmation = false
    @State var branchToCheckout: String = ""
    @State private var pendingHistoryCheckout: RepositorySheetRequest<String>?
    @State private var pendingRemoteBranchCheckout: RemoteBranchCheckoutTarget?
    @State private var showingRenameBranchSheet = false
    @State var branchToRename: String = ""
    @State var showingDetachedHeadConfirmation = false
    @State var tagToCheckout: String = ""
    @State var activeTagCheckoutCount = 0
    @State private var displayedTagDetails: RepositorySheetRequest<String>?
    @State var pendingTagDeletion: PendingTagDeletion?
    @State var pendingStashRef: String?
    @State var pendingStashAction: StashAction?
    @State private var activeStashActionCount = 0
    @State var pendingStashPaths: [String] = []
    @State var pendingProviderAccountSelection: PendingGitProviderAccountSelection?
    @State var providerAccountSelectionContinuation: CheckedContinuation<String?, Never>?
    @State private var lfsTrackingPath: String?
    @State private var hasOpenedPullRequests = false
    @State private var hasOpenedGitLFS = false
    @StateObject var syncState = SyncState()
    @StateObject var undoManager = GitUndoManager()
    @StateObject var pullRequestController: PullRequestController
    @StateObject var branchMergeDetectionController: BranchMergeDetectionController
    @State var pullRequestAccessDecision: FeatureAccessDecision?
    @State var featureAccessNotice: FeatureAccessNotice?
    @State var proUpgradePresentation: ProUpgradePresentation?
    @State var proUpgradeErrorMessage: String?
    @State private var repoIconName: String = "code-branch"
    @State private var backgroundErrorDetail: RepositoryBackgroundActivityItem?
    @State private var remoteURLString: String = ""
    @State var selectedBranchName: String? = nil
    @State private var pathComparisonWindow = PathComparisonWindowController()
    @State private var revisionBrowserWindow = RevisionBrowserWindowController()
    @State private var referenceDiffBase: String?
    @State private var referenceDiffTarget: String?
    @State private var referenceDiffTitle: String?
    @State private var isOpeningReferenceDiff = false
    @State private var branchComparisonWindow = BranchComparisonWindowController()
    @State private var pullPreselectedBranch: String? = nil
    @State var showingSearchModal = false
    @State private var repositorySettingsWindow = RepositorySettingsWindowController()
    @State var createPullRequestWindow = CreatePullRequestWindowController()
    @State var showingRepositorySettings = false
    @State var initiallySelectGitFlowSettings = false
    @State var pendingSearchFileOpenRequest: SearchFileOpenRequest?
    @State var searchFileOpenTask: Task<Void, Never>?
    @StateObject var commitRuleSyncController = RepositoryCommitRuleSyncController()
    @StateObject var protectedBranchCommitController = ProtectedBranchCommitController()
    @State var toolbarCommitMessage = ""
    @State var repoSettings = RepoSettings.defaults(currentBranch: nil, remotes: [])
    @State var gitFlowConfiguration = GitFlowConfiguration()
    @State var gitFlowFinishCheckpoint: GitFlowFinishCheckpoint?
    @State var gitFlowRecoveryIssue: GitFlowLocalStateIssue?
    @State var gitFlowConfigurationIssue: GitFlowLocalStateIssue?
    @State var didPerformInitialLoad = false
    @State var pendingGitFlowTopicKind: GitFlowTopicKind?
    @State var pendingGitFlowFinishPlan: RepositorySheetRequest<GitFlowTopicKind>?
    @State var gitFlowCurrentBranch = ""
    @State var gitFlowWorktreeRootURL: URL?
    @State var pendingConfirmedUndo: (entry: GitUndoEntry, action: GitUndoMenuAction)?
    @State var pendingCommitDropConfirmation: PendingCommitDropConfirmation?
    @State var pendingBranchDropConfirmation: PendingBranchDropConfirmation?
    @State var pendingPushBranchDropConfirmation: RepositorySheetRequest<String>?
    @State var pendingTagMoveConfirmation: RepositorySheetRequest<(tag: String, commit: GitDraggedCommit)>?
    @State private var pendingForcePushTagConfirmation: PendingForcePushTagConfirmation?
    @State private var pendingSubtreeOperation: PendingSubtreeOperation?
    @State private var isPerformingBranchDropOperation = false
    @State private var showingExternalEditorChooser = false
    @State private var externalEditorApplications: [IntegrationApplication] = []
    @State private var showingRepositoryAIChatPanel = false
    @AppStorage("repositoryAIChat.panelWidth") private var storedRepositoryAIChatPanelWidth = 340.0
    @State private var showingToolbarShortcutPopover = false
    @State private var releaseNotesPresentation: ReleaseNotesPresentation?
    @State private var promotionPresentation: ProPromotion?
    @State private var isPromotionHostVisible = false
    @Environment(\.sheetPresentationCoordinator) private var promotionSheetCoordinator
    @StateObject private var repositoryAIChatController: RepositoryAIChatController
    @ObservedObject var operationProgress: RepositoryOperationProgress
    private let customActionExecutor = CustomActionExecutor()
    @State private var customActionFilePaths: [String] = []
    @State private var historySelectionSink = HistoryCommitSelectionSink()
    @State private var customActionOutput: CustomActionOutputPresentation?

    init(
        repositoryURL: URL,
        initialShowsHistory: Bool? = nil,
        initialShowsPullRequests: Bool = false,
        providerAccountController: GitProviderAccountController,
        aiProviderController: AIProviderController,
        onOpenConnections: @escaping () -> Void = {},
        windowContext: RepositoryWindowContext,
        operationProgress: RepositoryOperationProgress
    ) {
        self.initialShowsHistory = initialShowsHistory
        _selectedItem = State(initialValue: initialShowsPullRequests ? .item(.pullRequests)
            : initialShowsHistory == true ? .item(.history) : .item(.fileStatus))
        self.repositoryURL = repositoryURL
        self.providerAccountController = providerAccountController
        self.aiProviderController = aiProviderController
        self.onOpenConnections = onOpenConnections
        self.windowContext = windowContext
        self.operationProgress = operationProgress
        let pullRequestController = PullRequestController(
            providerAccountController: providerAccountController,
            tokenVault: KeychainGitProviderTokenVault(),
            services: [.github: GitHubPullRequestService(), .gitlab: GitLabPullRequestService()],
            openURL: NSWorkspace.shared.open
        )
        let syncState = SyncState()
        syncState.shouldDeferAutomaticFetch = { [weak operationProgress] in
            operationProgress?.hasPendingBackgroundWork ?? false
        }
        let undoManager = GitUndoManager()
        let mutationContextProvider = RepositoryAIMutationContextProvider()
        let remoteOperationContextProvider = RepositoryAIRemoteOperationContextProvider()
        let mutationExecutor = RepositoryAIMutationExecutor(
            contextProvider: mutationContextProvider,
            undoManager: undoManager,
            syncState: syncState,
            operationProgress: operationProgress
        )
        _syncState = StateObject(wrappedValue: syncState)
        _undoManager = StateObject(wrappedValue: undoManager)
        _pullRequestController = StateObject(wrappedValue: pullRequestController)
        _branchMergeDetectionController = StateObject(wrappedValue: BranchMergeDetectionController(
            providerAccountController: providerAccountController
        ))
        _repositoryAIChatController = StateObject(wrappedValue: RepositoryAIChatController(
            repositoryURL: repositoryURL,
            providerController: aiProviderController,
            mutationExecutor: mutationExecutor,
            mutationContextProvider: mutationContextProvider,
            remoteOperationContextProvider: remoteOperationContextProvider,
            commitAllPreparer: RepositoryAICommitAllCoordinator(
                providerController: aiProviderController,
                contextProvider: mutationContextProvider,
                mutationExecutor: mutationExecutor
            ),
            pullRequestContextLoader: { number, repositoryURL in
                try await pullRequestController.repositoryAIContext(number: number, repositoryURL: repositoryURL)
            },
            pullRequestFingerprintLoader: { number, repositoryURL in
                try await pullRequestController.repositoryAIFingerprint(number: number, repositoryURL: repositoryURL)
            }
        ))
    }

    var body: some View {
        mainContent
            .alert("Error", isPresented: $syncState.showingError, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(syncState.errorMessage ?? "An unknown error occurred")
            })
            .alert("Conflict", isPresented: $syncState.showingConflict, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(syncState.conflictMessage ?? "Merge conflicts detected.")
            })
            .alert("Info", isPresented: $syncState.showingInfo, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(syncState.infoMessage ?? "")
            })
            .alert(item: $featureAccessNotice) { notice in
                featureAccessAlert(for: notice)
            }
            .replacingSheet(item: $proUpgradePresentation) { presentation in
                ProUpgradeSheet(
                    feature: presentation.feature,
                    isSignedIn: accountController.account != nil,
                    isOpening: accountController.openingWebDestination == .pricing,
                    errorMessage: proUpgradeErrorMessage,
                    onCancel: dismissProUpgradeSheet,
                    onPrimaryAction: performProUpgradePrimaryAction
                )
            }
            .replacingSheet(item: $promotionPresentation) { promotion in
                ProPromotionSheet(promotion: promotion) {
                    Task { await accountController.openPricingOnWeb() }
                }
                .onAppear { ProPromotionPresentationStore.shared.didPresent(promotion) }
                .onDisappear { ProPromotionPresentationStore.shared.releasePresentation() }
            }
            .replacingSheet(item: $releaseNotesPresentation) { presentation in
                ReleaseNotesSheet(presentation: presentation)
            }
            .replacingSheet(item: $backgroundErrorDetail) { item in
                if case .failed(_, let detail) = item.state {
                    RepositoryBackgroundErrorDetailSheet(title: "\(item.title) failed", message: detail)
                }
            }
            .confirmationDialog(
                "Open Repository in Editor",
                isPresented: $showingExternalEditorChooser
            ) {
                ForEach(externalEditorApplications) { application in
                    Button(application.displayName) {
                        launchRepository(in: application)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose an installed editor for this repository.")
            }
            .confirmationDialog(
                pendingConfirmedUndo?.action == .redo ? "Confirm Git Redo" : "Confirm Git Undo",
                isPresented: Binding(
                    get: { pendingConfirmedUndo != nil },
                    set: { isPresented in
                        if !isPresented {
                            if let pending = pendingConfirmedUndo {
                                switch pending.action {
                                case .undo:
                                    undoManager.restoreUndo(pending.entry)
                                case .redo:
                                    undoManager.restoreRedo(pending.entry)
                                }
                            }
                            pendingConfirmedUndo = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(pendingConfirmedUndo?.action == .redo ? "Redo" : "Undo", role: .destructive) {
                    guard let pending = pendingConfirmedUndo else { return }
                    pendingConfirmedUndo = nil
                    let operation = pending.action == .redo ? pending.entry.redoOperation : pending.entry.undoOperation
                    if GitUndoExecutor.canRunInBackground(operation) {
                        runUndoEntry(pending.entry, menuAction: pending.action)
                    } else {
                        runRepositoryOperation(pending.action == .redo ? "Redoing Git action..." : "Undoing Git action...") {
                            await executeUndoEntry(pending.entry, menuAction: pending.action)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(pendingConfirmedUndo?.entry.confirmationMessage ?? "")
            }
            .confirmationDialog(
                "Force Push Tag",
                isPresented: Binding(
                    get: { pendingForcePushTagConfirmation != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingForcePushTagConfirmation = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Force Push", role: .destructive) {
                    guard let confirmation = pendingForcePushTagConfirmation else { return }
                    pendingForcePushTagConfirmation = nil
                    runBackgroundRemoteOperation(
                        "Force-pushing \(confirmation.tag) to \(confirmation.remote)",
                        remotes: [confirmation.remote]
                    ) { credentialResolver in
                        await syncState.performBackgroundPush(
                            options: GitStatusService.PushOptions(
                                remote: confirmation.remote,
                                tags: [confirmation.tag],
                                forceTags: true
                            ),
                            repositoryURL: repositoryURL,
                            undoManager: undoManager,
                            credentialResolver: credentialResolver
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let confirmation = pendingForcePushTagConfirmation {
                    Text("Replace tag '\(confirmation.tag)' on '\(confirmation.remote)' with the local tag target? This rewrites the published tag and may retrigger release automation.")
                }
            }
            .replacingSheet(isPresented: $showingCommitSheet) { commitSheet }
            .replacingSheet(item: $customActionOutput) { presentation in
                CustomActionOutputSheet(
                    result: presentation.result,
                    onRunAgain: {
                        customActionOutput = nil
                        runCustomAction(
                            id: presentation.result.action.id,
                            context: presentation.result.context,
                            surface: invocationSurface(for: presentation.result.context)
                        )
                    },
                    onClose: { customActionOutput = nil }
                )
            }
            .replacingSheet(item: protectedBranchWarningOutsideCommit, onDismiss: { protectedBranchCommitController.finish(.cancel) }) { warning in
                ProtectedBranchCommitSheet(warning: warning, skipWarnings: $repoSettings.skipProtectedBranchCommitWarnings) { decision in
                    protectedBranchCommitController.finish(decision)
                }
                .onChange(of: repoSettings.skipProtectedBranchCommitWarnings) { _, _ in
                    commitRulePreferenceChanged()
                }
            }
            .replacingSheet(isPresented: $showingPullSheet) { pullSheet }
            .replacingSheet(isPresented: $showingPushSheet, onDismiss: forcePushSheetDismissed) { pushSheet }
            .replacingSheet(item: $pendingBranchForcePush) { request in
                forcePushPreparationSheet(for: request)
            }
            .replacingSheet(isPresented: $showingFetchSheet) { fetchSheet }
            .replacingSheet(isPresented: $showingAddSubmoduleSheet) { addSubmoduleSheet }
            .replacingSheet(isPresented: $showingAddLinkSubtreeSheet) { addLinkSubtreeSheet }
            .replacingSheet(item: $branchSheetPresentation) { presentation in
                branchSheet(startPoint: presentation.startPoint)
            }
            .replacingSheet(isPresented: $showingTagSheet, onDismiss: resetTagSheet) { tagSheet }
            .replacingSheet(isPresented: $showingNewTagSheet) { newTagSheet }
            .replacingSheet(isPresented: tagDetailsSheetPresented) {
                if let request = displayedTagDetails {
                    RepositorySheetLoadingView(title: "Tag Details", load: {
                        try await GitStatusService.shared.tagDetails(name: request.input, in: repositoryURL)
                    }, onCancel: { displayedTagDetails = nil }) { details in
                        TagDetailsSheet(details: details) { displayedTagDetails = nil }
                    }
                    .id(request.id)
                }
            }
            .replacingSheet(isPresented: $showingMergeSheet) { mergeSheet }
            .replacingSheet(isPresented: $showingStashSheet) { stashSheet }
            .onChange(of: showingRepositorySettings) { _, isPresented in
                if isPresented {
                    presentRepositorySettingsWindow()
                } else {
                    repositorySettingsWindow.close()
                }
            }
            .replacingSheet(item: $pendingGitFlowTopicKind) { kind in
                startGitFlowSheet(for: kind)
            }
            .replacingSheet(item: $pendingGitFlowFinishPlan) { request in
                RepositorySheetLoadingView(title: "Finish \(request.input.displayName)", load: {
                    try await loadGitFlowFinishPlan(request.input)
                }, onCancel: { pendingGitFlowFinishPlan = nil }) { plan in
                    finishGitFlowSheet(for: plan)
                }
                .id(request.id)
            }
            .replacingSheet(item: providerAccountSelectionOutsideOperationSheet) { selection in
                GitProviderAccountSelectionSheet(
                    selection: selection,
                    onSelect: { accountID in
                        completeProviderAccountSelection(with: accountID)
                    },
                    onCancel: {
                        completeProviderAccountSelection(with: nil)
                    }
                )
            }
            .replacingSheet(item: $pendingSearchFileOpenRequest) { request in
                SearchFileOpenSheet(request: request) { application, rememberChoice in
                    pendingSearchFileOpenRequest = nil
                    if rememberChoice {
                        appState.preferredSearchFileApplicationBundleIdentifier = application.bundleIdentifier
                    }
                    openSearchFile(
                        request.relativePath,
                        lineTarget: request.lineTarget,
                        using: application
                    )
                }
            }
            .replacingSheet(isPresented: stashActionSheetBinding) { stashActionSheet }
            .replacingSheet(item: $pendingCommitDropConfirmation) { confirmation in
                commitDropConfirmationSheet(for: confirmation)
            }
            .replacingSheet(item: $pendingBranchDropConfirmation) { confirmation in
                branchDropConfirmationSheet(for: confirmation)
            }
            .replacingSheet(item: $pendingTagMoveConfirmation) { confirmation in
                tagMoveConfirmationSheet(for: confirmation)
            }
            .replacingSheet(item: $pendingSubtreeOperation) { pending in
                SubtreeOperationConfirmationSheet(
                    operation: pending.operation,
                    entry: pending.entry,
                    onConfirm: {
                        try await performSubtreeOperation(pending)
                    },
                    onCompleted: {
                        pendingSubtreeOperation = nil
                    },
                    onRunRepositoryOperation: runRepositoryOperation
                )
            }
            .replacingSheet(item: $pendingPushBranchDropConfirmation) { request in
                RepositorySheetLoadingView(title: "Push Branch", load: {
                    try await loadPushBranchDropConfirmation(request.input)
                }, onCancel: { pendingPushBranchDropConfirmation = nil }) { confirmation in
                    GitDragActionConfirmationSheet(
                        title: "Push Branch",
                        message: "Push \(confirmation.branch) to \(confirmation.remoteBranch)?",
                        targetBranchName: confirmation.remoteBranch,
                        commits: [], primaryActionTitle: "Push",
                        onConfirm: {
                            pendingPushBranchDropConfirmation = nil
                            runRepositoryOperation("Pushing \(confirmation.branch) to \(confirmation.remote)...") {
                                await performConfirmedBranchPush(confirmation)
                            }
                        },
                        onCancel: { pendingPushBranchDropConfirmation = nil }
                    )
                }
                .id(request.id)
            }
            .replacingSheet(isPresented: $showingRenameBranchSheet) { renameSheet }
            .replacingSheet(isPresented: $showingCheckoutConfirmation) {
                CheckoutConfirmationSheet(branchName: branchToCheckout) { stash in
                    runRepositoryOperation("Checking out \(branchToCheckout)...") {
                        await performCheckout(ref: branchToCheckout, stash: stash)
                    }
                }
            }
            .replacingSheet(item: $pendingHistoryCheckout) { request in
                RepositorySheetLoadingView(title: "Checkout \(request.input)", load: {
                    let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
                    return remoteBranchCheckoutTarget(for: request.input, remotes: remotes)
                }, onCancel: { pendingHistoryCheckout = nil }) { target in
                    if let target {
                        RemoteBranchCheckoutSheet(target: target) { localBranch, trackRemote in
                            runRepositoryOperation("Checking out \(localBranch)...") {
                                await performRemoteBranchCheckout(target: target, localBranch: localBranch, trackRemote: trackRemote)
                            }
                        }
                    } else {
                        CheckoutConfirmationSheet(branchName: request.input) { stash in
                            runRepositoryOperation("Checking out \(request.input)...") {
                                await performCheckout(ref: request.input, stash: stash)
                            }
                        }
                    }
                }
                .id(request.id)
            }
            .replacingSheet(item: $pendingRemoteBranchCheckout) { target in
                RemoteBranchCheckoutSheet(target: target) { localBranch, trackRemote in
                    runRepositoryOperation("Checking out \(localBranch)...") {
                        await performRemoteBranchCheckout(
                            target: target,
                            localBranch: localBranch,
                            trackRemote: trackRemote
                        )
                    }
                }
            }
            .alert("Confirm change working copy", isPresented: $showingDetachedHeadConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("OK") {
                    runRepositoryOperation("Checking out \(tagToCheckout)...") {
                        await performTagCheckout(tag: tagToCheckout)
                    }
                }
            } message: {
                Text("Are you sure you want to checkout '\(tagToCheckout)'?\n\nDoing so will make your working copy a 'detached HEAD', which means you won't be on a branch anymore. If you want to commit after this you'll probably want to either checkout a branch again, or create a new branch. Is this ok?")
            }
            .replacingSheet(isPresented: tagDeletionConfirmationPresented) {
                if let confirmation = pendingTagDeletion {
                    deleteTagConfirmationSheet(for: confirmation)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await reconcileCommitRulePreference() }
                // Debounced so rapid app switching does not refresh and fetch on every activation.
                appActivationSyncTask?.cancel()
                appActivationSyncTask = Task {
                    do {
                        try await Task.sleep(for: Self.appActivationSyncDebounce)
                    } catch {
                        return
                    }
                    if repoSettings.resolvedRefreshOnAppActive(
                        globalValue: appState.refreshOnAppActive
                    ) {
                        await syncState.refresh(repositoryURL: repositoryURL, force: true)
                        NotificationCenter.default.post(
                            name: .repositoryLocalStateDidRefresh,
                            object: nil,
                            userInfo: ["repositoryURL": repositoryURL]
                        )
                        var didFetchRemoteRefs = false
                        if let credentialResolver = await credentialResolverForFetch(
                            options: GitStatusService.FetchOptions()
                        ) {
                            didFetchRemoteRefs = await syncState.performAutomaticFetch(
                                options: GitStatusService.FetchOptions(),
                                repositoryURL: repositoryURL,
                                credentialResolver: credentialResolver,
                                force: true
                            )
                        }
                        if didFetchRemoteRefs {
                            await syncState.refresh(repositoryURL: repositoryURL, force: true)
                            NotificationCenter.default.post(
                                name: .repositoryRemoteRefsDidRefresh,
                                object: nil,
                                userInfo: ["repositoryURL": repositoryURL]
                            )
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSearchModal)) { notification in
                guard windowContext.owns(notification) else { return }
                showingSearchModal = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toolbarAction)) { notification in
                guard windowContext.owns(notification),
                      let action = notification.userInfo?["action"] as? ToolbarAction else { return }
                handleToolbarAction(action)
            }
            .onReceive(NotificationCenter.default.publisher(for: .gitUndoAction)) { notification in
                guard windowContext.owns(notification),
                      let action = notification.userInfo?["action"] as? GitUndoMenuAction else { return }
                handleGitUndoMenuAction(action)
            }
            .onReceive(NotificationCenter.default.publisher(for: .repositoryOperationProgressBegan)) { notification in
                if let event = notification.userInfo?["event"] as? RepositoryOperationProgressEvent {
                    operationProgress.begin(event)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .repositoryOperationProgressEnded)) { notification in
                if let id = notification.userInfo?["id"] as? UUID {
                    operationProgress.end(id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .repositoryOperationProgressCancelRequested)) { notification in
                if let id = notification.userInfo?["id"] as? UUID {
                    operationProgress.requestCancel(id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .advancedClearSessionCaches)) { _ in
                pullRequestController.clearSessionCaches()
            }
    }

    private var mainLayout: some View {
        ZStack {
            rootView

            if showingRepositoryAIChatPanel {
                RepositoryAIChatOverlayPanel(
                    width: repositoryAIChatPanelWidthBinding,
                    onDismiss: { showingRepositoryAIChatPanel = false },
                    repositoryAIController: repositoryAIChatController,
                    aiProviderController: aiProviderController,
                    repositoryChatAccess: featureAccessController.decision(
                        for: .repositoryChat,
                        entitlement: accountController.entitlement
                    ),
                    isSignedIn: accountController.account != nil,
                    onRequestRepositoryChatAccess: requestRepositoryChatAccess,
                    onExecuteRemoteOperation: executeRepositoryAIRemoteOperation
                )
            }

            if showingSearchModal {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingSearchModal = false
                        }

                    SearchModalView(
                        repositoryURL: repositoryURL,
                        initialFilter: appState.searchFilter,
                        onDismiss: { showingSearchModal = false },
                        onSelectFilter: { appState.searchFilter = $0 },
                        onSelect: { action in
                            handleSearchAction(action)
                            showingSearchModal = false
                        }
                    )
                    .padding(.top, 72)
                    .padding(.horizontal, 24)
                }
                .transition(.opacity)
            }

            if let activeOperation = operationProgress.activeOperation {
                RepositoryOperationOverlayView(
                    operation: activeOperation,
                    onCancel: { operationProgress.cancelActiveOperation() }
                )
            }

            MainWindowKeyboardHandler(showingSearchModal: $showingSearchModal)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .overlay(
            GeometryReader { geo in
                Color.clear.preference(key: WindowWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(WindowWidthKey.self) { newWidth in
            windowWidth = newWidth
        }
        .toolbar { toolbarContent }
        .toolbar(removing: .title)
        .navigationTitle(repositoryURL.lastPathComponent)
        .focusedSceneValue(\.toolbarAction, toolbarActionBinding)
        .focusedSceneValue(\.toolbarActionState, ToolbarActionState(
            isSyncing: syncState.isAnySyncing,
            stagedCount: syncState.stagedBadgeCount,
            stashableCount: syncState.stashableCount
        ))
        .focusedSceneValue(\.gitFlowCommandState, gitFlowCommandState)
        .focusedSceneValue(\.customActionCommandState, customActionCommandState)
        .frame(minWidth: 1100 * appState.textSize.scale, minHeight: 600)
    }

    private var mainLoading: some View {
        mainLayout
            .task { await performInitialLoad() }
            .task {
                releaseNotesPresentation = await ReleaseNotesPresentationStore.shared.claimPresentation()
                if releaseNotesPresentation == nil {
                    await presentPromotionIfAvailable()
                }
            }
            .task(id: gitFlowConfigurationSyncTaskID) {
                await reconcileCommitRulePreference()
            }
            .task(id: gitFlowConfigurationSyncTaskID) {
                await reconcileGitFlowConfigurationWithCloud()
            }
            .task(id: pullRequestAccessTaskID) {
                guard selectedItem == .item(.pullRequests) else { return }
                pullRequestAccessDecision = nil
                _ = await authorizePullRequestAccess(presentNotice: false)
            }
    }

    private var mainContent: some View {
        mainLoading
        .onChange(of: releaseNotesPresentation == nil) { _, dismissed in
            if dismissed {
                Task { await presentPromotionIfAvailable() }
            }
        }
        .onChange(of: appState.autoFetchEnabled) { _, globalAutoFetchEnabled in
            startBackgroundSyncIfLoaded(globalAutoFetchEnabled: globalAutoFetchEnabled)
        }
        .onChange(of: selectedItem) { _, newItem in
            if newItem != .item(.gitLFS) { lfsTrackingPath = nil }
            if case .branch(let name) = newItem {
                selectedBranchName = name
            } else if case .tag(let name) = newItem {
                selectedBranchName = name
            } else if case .remoteBranch(let name) = newItem {
                selectedBranchName = name
            } else if case .worktree(let worktreeURL) = newItem {
                selectedBranchName = nil
                revealWorktreeInHistory(worktreeURL)
            } else {
                selectedBranchName = nil
            }

            if isOpeningReferenceDiff {
                isOpeningReferenceDiff = false
            } else {
                clearReferenceDiff()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryCurrentBranchDidChange)) { notification in
            guard let changedRepositoryURL = notification.userInfo?["repositoryURL"] as? URL,
                  changedRepositoryURL.standardizedFileURL == repositoryURL.standardizedFileURL else { return }
            Task {
                let branch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
                await MainActor.run { gitFlowCurrentBranch = branch }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPullRequestsFromUserNotification)) { notification in
            guard let repositoryPath = notification.userInfo?[
                PullRequestUserNotification.repositoryPathKey
            ] as? String,
                  URL(fileURLWithPath: repositoryPath).standardizedFileURL == repositoryURL.standardizedFileURL else {
                return
            }
            windowContext.window?.makeKeyAndOrderFront(nil)
            selectedItem = .item(.pullRequests)
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitFlowMenuAction)) { notification in
            guard windowContext.owns(notification),
                  let action = notification.userInfo?["action"] as? GitFlowMenuAction else { return }
            handleGitFlowMenuAction(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .customActionMenuAction)) { notification in
            guard windowContext.owns(notification),
                  let id = notification.userInfo?["id"] as? UUID,
                  let surface = notification.userInfo?["surface"] as? CustomActionInvocationSurface else { return }
            runCustomAction(id: id, context: customActionCommandState.context, surface: surface)
        }
        .onChange(of: repositoryAIChatController.workflowAccessNotice) { _, notice in
            guard let notice else { return }
            if notice.denial == .requiresPro {
                proUpgradeErrorMessage = nil
                proUpgradePresentation = ProUpgradePresentation(feature: .repositoryAIActions)
            } else {
                featureAccessNotice = notice
            }
            repositoryAIChatController.workflowAccessNotice = nil
        }
        .onAppear {
            isPromotionHostVisible = true
            repositoryAIChatController.workflowAccessDecision = { [featureAccessController, accountController] in
                featureAccessController.decision(
                    for: .repositoryAIActions,
                    entitlement: accountController.entitlement
                )
            }
            windowContext.attachUndoManager(undoManager, syncState: syncState, for: repositoryURL)
            operationProgress.waitBeforeBackgroundOperation = { [weak syncState] in
                await syncState?.waitForAutomaticFetchToFinish()
            }
            OpenRepositoryRegistry.shared.register(repositoryURL)
        }
        .onDisappear {
            appActivationSyncTask?.cancel()
            appActivationSyncTask = nil
            repositorySettingsWindow.close()
            branchComparisonWindow.close()
            createPullRequestWindow.close()
            isPromotionHostVisible = false
            if promotionPresentation != nil {
                ProPromotionPresentationStore.shared.releasePresentation()
            }
            protectedBranchCommitController.finish(.cancel)
            repositoryAIChatController.invalidatePendingMutation(
                reason: "Repository window closed.",
                appendTranscript: false
            )
            repositoryAIChatController.windowWillClose()
            OpenRepositoryRegistry.shared.unregister(repositoryURL)
            syncState.stopBackgroundSync()
            operationProgress.cancelAllBackground()
        }
    }

    private func presentPromotionIfAvailable() async {
        guard let promotion = await ProPromotionPresentationStore.shared.claimPresentation() else { return }
        guard !Task.isCancelled, isPromotionHostVisible, promotionSheetCoordinator?.isPresenting != true,
              accountController.presentedSheet == nil,
              !accountController.isLoading,
              (accountController.account == nil || accountController.entitlementLastUpdatedAt != nil),
              promotion.audience.contains(accountController.account == nil ? .free : accountController.entitlement.effectivePlan) else {
            ProPromotionPresentationStore.shared.releasePresentation()
            return
        }
        promotionPresentation = promotion
    }

    func runRepositoryOperation(_ message: String, _ operation: @escaping () async -> Void) {
        operationProgress.run(message: message, operation: operation)
    }

    private var customActionCommandState: CustomActionCommandState {
        let surface: CustomActionInvocationSurface
        let context: CustomActionInvocationContext
        switch selectedItem {
        case .item(.fileStatus):
            surface = customActionFilePaths.isEmpty ? .repository : .selectedFiles
            context = CustomActionInvocationContext(
                repositoryURL: repositoryURL,
                filePaths: customActionFilePaths,
                commitHashes: []
            )
        case .item(.history), .branch, .worktree, .tag, .remoteBranch, .head:
            surface = historySelectionSink.commitHashes.isEmpty ? .repository : .selectedCommits
            context = CustomActionInvocationContext(
                repositoryURL: repositoryURL,
                filePaths: [],
                commitHashes: historySelectionSink.commitHashes
            )
        default:
            surface = .repository
            context = CustomActionInvocationContext(
                repositoryURL: repositoryURL,
                filePaths: [],
                commitHashes: []
            )
        }
        return CustomActionCommandState(
            context: context,
            surface: surface,
            hasActiveOperation: operationProgress.activeOperation != nil
        )
    }

    private func invocationSurface(for context: CustomActionInvocationContext) -> CustomActionInvocationSurface {
        if !context.filePaths.isEmpty { return .selectedFiles }
        if !context.commitHashes.isEmpty { return .selectedCommits }
        return .repository
    }

    private func runCustomAction(
        id: UUID,
        context: CustomActionInvocationContext,
        surface: CustomActionInvocationSurface
    ) {
        guard operationProgress.activeOperation == nil,
              let action = customActionStore.action(id: id) else { return }
        if let reason = CustomActionValidator.unavailableReason(
            for: action,
            surface: surface,
            context: context,
            isTrusted: customActionStore.isTrusted(action)
        ) {
            syncState.showError(reason)
            return
        }

        operationProgress.run(message: "Running \(action.name)...") {
            let result = await customActionExecutor.execute(action: action, context: context)
            await syncState.refresh(repositoryURL: repositoryURL, force: true)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
            if result.status != .succeeded || action.alwaysShowOutput {
                customActionOutput = CustomActionOutputPresentation(result: result)
            } else {
                syncState.showInfo("\(action.name) completed successfully.")
            }
        }
    }

    private func clearReferenceDiff() {
        referenceDiffBase = nil
        referenceDiffTarget = nil
        referenceDiffTitle = nil
    }

    private var checkoutRequest: (String, Bool) -> Void {
        { ref, isTag in
            if isTag {
                tagToCheckout = ref
                if repoSettings.confirmDetachedHeadCheckout {
                    showingDetachedHeadConfirmation = true
                } else {
                    Task { await performTagCheckout(tag: ref) }
                }
            } else {
                pendingHistoryCheckout = RepositorySheetRequest(input: ref)
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        NavigationSplitView {
            sidebarPane
        } detail: {
            detailPane
        }
    }

    private var sidebarPane: some View {
        SidebarView(
            repositoryURL: repositoryURL,
            selection: $selectedItem,
            undoManager: undoManager,
            currentBranchFallbackSyncStatus: currentBranchFallbackSyncStatus,
            stagedFileCount: syncState.stagedBadgeCount,
            changedFileCount: syncState.changedFileCount,
            defaultRemoteName: repoSettings.defaultRemoteName,
            isAccountMenuDisabled: operationProgress.activeOperation != nil,
            gitFlowRoleDisplayMode: gitFlowConfiguration.roleDisplayMode,
            gitFlowConfiguration: gitFlowConfiguration,
            gitFlowFinishCheckpoint: gitFlowFinishCheckpoint,
            gitFlowRecoveryIssue: gitFlowRecoveryIssue,
            isGitFlowOperationDisabled: operationProgress.activeOperation != nil,
            isBranchSyncing: { branch in
                (syncState.isUpdatingCurrentBranch && syncState.activeSyncBranch == branch)
                    || BranchSyncBadgePolicy.shouldShowLoading(
                    for: branch,
                    isPulling: syncState.isPulling,
                    isPushing: syncState.isPushing,
                    activeSyncBranch: syncState.activeSyncBranch
                )
            },
            activeSyncBranchName: (syncState.isUpdatingCurrentBranch || syncState.isPulling || syncState.isPushing) ? syncState.activeSyncBranch : nil,
            canUpdateCurrentBranch: canUpdateCurrentBranch,
            branchMergeDetectionController: branchMergeDetectionController,
            showMergedBranchHints: repoSettings.showMergedBranchHints,
            onRequestCheckout: { ref, isTag in
                if isTag {
                    tagToCheckout = ref
                    if repoSettings.confirmDetachedHeadCheckout {
                        showingDetachedHeadConfirmation = true
                    } else {
                        Task {
                            await performTagCheckout(tag: ref)
                        }
                    }
                } else {
                    branchToCheckout = ref
                    showingCheckoutConfirmation = true
                }
            },
            onRequestRemoteBranchCheckout: { target in
                pendingRemoteBranchCheckout = target
            },
            onRequestFetchBranch: { branch in
                Task {
                    let remote = await trackedRemote(for: branch)
                    runRemoteOperation("Fetching \(branch)...", remotes: remote.map { [$0] } ?? []) { credentialResolver in
                        guard await waitForBackgroundRemoteActivity() else { return }
                        await syncState.performFetchAndFastForwardBranch(
                            branch: branch,
                            repositoryURL: repositoryURL,
                            credentialResolver: credentialResolver
                        )
                    }
                }
            },
            onRequestPullRemoteBranch: { remote, branch in
                runRemoteOperation("Pulling \(remote)/\(branch)...", remotes: [remote]) { credentialResolver in
                    guard await waitForBackgroundRemoteActivity() else { return }
                    await syncState.performPull(
                        remote: remote,
                        branch: branch,
                        options: GitStatusService.PullOptions(),
                        repositoryURL: repositoryURL,
                        undoManager: undoManager,
                        credentialResolver: credentialResolver
                    )
                }
            },
            onRequestPullTracked: { branch in
                Task {
                    let remote = await trackedRemote(for: branch)
                    runRemoteOperation("Pulling \(branch)...", remotes: remote.map { [$0] } ?? []) { credentialResolver in
                        guard await waitForBackgroundRemoteActivity() else { return }
                        await syncState.performPullBranch(
                            branch: branch,
                            repositoryURL: repositoryURL,
                            undoManager: undoManager,
                            credentialResolver: credentialResolver
                        )
                    }
                }
            },
            onRequestPushToTracked: { branch in
                Task {
                    let remote = await trackedRemote(for: branch)
                    guard let remote,
                          let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else { return }
                    let remoteBranch = String(upstream.dropFirst(remote.count + 1))
                    pushSheetSelection = (branch, remote, remoteBranch)
                    showingPushSheet = true
                }
            },
            onRequestForcePushToTracked: requestTrackedBranchForcePush,
            onRequestForcePushBranchToRemote: { branch, remote in
                requestBranchForcePush(branch: branch, remote: remote, remoteBranch: branch)
            },
            onRequestUpdateCurrentBranch: requestCurrentBranchIntegrationUpdate,
            onRequestRenameBranch: { branch in
                branchToRename = branch
                showingRenameBranchSheet = true
            },
            onRequestCreatePullRequest: { branch in
                prepareCreatePullRequest(branch: branch)
            },
            onRequestCreateBranchFromBranch: { branch in
                presentBranchSheet(startPoint: .branch(branch))
            },
            onRequestCreateTagFromBranch: { branch in
                presentTagSheetFromBranchTip(branch)
            },
            onRequestTagDetails: { tag in
                presentTagDetails(tag)
            },
            onRequestDiffTagAgainstCurrent: { tag in
                clearReferenceDiff()
                referenceDiffBase = tag
                referenceDiffTarget = "HEAD"
                referenceDiffTitle = "Diff: \(tag) against Current (HEAD)"
                isOpeningReferenceDiff = selectedItem != .item(.history)
                selectedItem = .item(.history)
            },
            onRequestCompareBranches: { target, current in
                branchComparisonWindow.show(
                    baseRef: current.isEmpty || current == "HEAD" ? "" : "refs/heads/\(current)",
                    targetRef: target,
                    in: repositoryURL
                )
            },
            onRequestPushTagToRemote: { tag, remote in
                runBackgroundRemoteOperation("Pushing \(tag) to \(remote)", remotes: [remote]) { credentialResolver in
                    let options = GitStatusService.PushOptions(
                        remote: remote,
                        tags: [tag]
                    )
                    return await syncState.performBackgroundPush(
                        options: options,
                        repositoryURL: repositoryURL,
                        undoManager: undoManager,
                        credentialResolver: credentialResolver
                    )
                }
            },
            onRequestForcePushTagToRemote: { tag, remote in
                pendingForcePushTagConfirmation = PendingForcePushTagConfirmation(
                    tag: tag,
                    remote: remote
                )
            },
            onRequestDeleteTag: { tag in
                pendingTagDeletion = PendingTagDeletion(tag: tag, remotes: [])
            },
            onRequestRebaseOnto: { branch in
                runRepositoryOperation("Rebasing onto \(branch)...") {
                    await syncState.performRebaseOnto(
                        branch: branch,
                        repositoryURL: repositoryURL,
                        undoManager: undoManager
                    )
                }
            },
            onRequestMergeBranchIntoCurrent: { branch in
                runRepositoryOperation("Merging \(branch)...") {
                    await syncState.performMerge(
                        branch: branch,
                        options: GitStatusService.MergeOptions(),
                        repositoryURL: repositoryURL
                    )
                }
            },
            onRequestPushBranchToRemote: { branch, remote in
                pushSheetSelection = (branch, remote, branch)
                showingPushSheet = true
            },
            onRequestTrackRemoteBranch: { branch, upstream in
                runRepositoryOperation(upstream == nil ? "Clearing upstream for \(branch)..." : "Tracking \(upstream!) for \(branch)...") {
                    await syncState.performTrackRemoteBranch(
                        branch: branch,
                        upstream: upstream,
                        repositoryURL: repositoryURL
                    )
                }
            },
            onRequestCreatePullRequestForRemote: { remote, branch in
                runRepositoryOperation("Preparing pull request for \(remote)/\(branch)...") {
                    await openPullRequest(remote: remote, branch: branch)
                }
            },
            onRequestApplyStash: { ref in
                requestStashAction(ref: ref, action: .apply)
            },
            onRequestDeleteStash: { ref in
                requestStashAction(ref: ref, action: .delete)
            },
            onRequestOpenWorktree: { path in
                openWorktreeInNewWindow(at: path)
            },
            onRequestOpenWorktreeInTerminal: { path in
                openWorktreeInTerminal(at: path)
            },
            onRequestOpenSubmodule: { path in
                openWorktreeInNewWindow(at: path)
            },
            onRequestShowSubmoduleInFinder: { path in
                NSWorkspace.shared.activateFileViewerSelecting([path])
            },
            onRequestOpenSubmoduleInTerminal: { path in
                openWorktreeInTerminal(at: path)
            },
            onRequestAddSubmodule: {
                showingAddSubmoduleSheet = true
            },
            onRequestAddLinkSubtree: {
                showingAddLinkSubtreeSheet = true
            },
            onRequestCreateBranch: {
                presentBranchSheet(startPoint: nil)
            },
            onRequestCreateTag: {
                showingNewTagSheet = true
            },
            onRequestCreatePullRequestFromWorkspace: {
                prepareCreatePullRequest()
            },
            onRequestBranchMergeUpgrade: {
                proUpgradeErrorMessage = nil
                proUpgradePresentation = ProUpgradePresentation(feature: .branchMergeDetection)
            },
            onRequestShowSubtreeInFinder: { path in
                NSWorkspace.shared.activateFileViewerSelecting([path])
            },
            onRequestOpenSubtreeInTerminal: { path in
                openWorktreeInTerminal(at: path)
            },
            onRequestPullSubtree: { entry in
                pendingSubtreeOperation = PendingSubtreeOperation(operation: .pull, entry: entry)
            },
            onRequestPushSubtree: { entry in
                pendingSubtreeOperation = PendingSubtreeOperation(operation: .push, entry: entry)
            },
            onRequestUpdateSubtreeLink: { entry in
                let registry = GitSubtreeRegistry()
                try await registry.save(entry, in: repositoryURL)
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            },
            onRequestUnlinkSubtree: { entry in
                try await GitStatusService.shared.unlinkSubtree(id: entry.id, in: repositoryURL)
            },
            onRequestInitializeSubmodule: { path in
                runRepositoryOperation("Initializing \(path)...") {
                    await initializeSubmodule(at: path)
                }
            },
            onRequestUpdateSubmodule: { path, mode in
                let action = mode == .recordedCommit ? "Updating \(path) to recorded commit..." : "Updating \(path) from remote..."
                runRepositoryOperation(action) {
                    await updateSubmodule(at: path, mode: mode)
                }
            },
            onRequestSynchronizeSubmoduleURL: { path in
                runRepositoryOperation("Synchronizing \(path)...") {
                    await synchronizeSubmoduleURL(at: path)
                }
            },
            onRequestUpdateSubmoduleSettings: { path, url, branch in
                try await GitStatusService.shared.updateSubmoduleSettings(
                    path: path,
                    url: url,
                    branch: branch,
                    in: repositoryURL
                )
            },
            onRequestDeinitializeSubmodule: { path, force in
                try await GitStatusService.shared.deinitializeSubmodule(
                    path: path,
                    force: force,
                    in: repositoryURL
                )
            },
            onRequestRemoveSubmodule: { path, force in
                try await GitStatusService.shared.removeSubmodule(
                    path: path,
                    force: force,
                    in: repositoryURL
                )
            },
            onRequestSearch: {
                showingSearchModal = true
            },
            onRequestStartGitFlow: { kind in
                requestStartGitFlow(kind)
            },
            onRequestFinishGitFlow: { kind in
                requestFinishGitFlow(kind)
            },
            onRequestResumeGitFlowFinish: {
                resumeGitFlowFinish()
            },
            onRequestAbortGitFlowFinish: {
                abortGitFlowFinish()
            },
            onRequestEditGitFlow: {
                requestPresentGitFlowSettings()
            },
            onRequestDisableGitFlow: disableGitFlow,
            onRequestDragDrop: { request in
                handleDragDropRequest(request)
            },
            onRunRepositoryOperation: runRepositoryOperation,
            onRunBackgroundRemoteBranchDeletion: runBackgroundRemoteBranchDeletion
        )
        .navigationSplitViewColumnWidth(
            min: 200 * appState.textSize.scale,
            ideal: 220 * appState.textSize.scale,
            max: 600
        )
    }

    private var currentBranchFallbackSyncStatus: BranchSyncStatus? {
        let ahead = syncState.pushBadgeCount
        let behind = syncState.pullBadgeCount
        return BranchSyncStatus(ahead: ahead, behind: behind)
    }

    private var canUpdateCurrentBranch: Bool {
        syncState.commitBadgeCount == 0
            && syncState.inProgressOperation == nil
            && !syncState.isAnySyncing
            && operationProgress.activeOperation == nil
    }

    private func requestCurrentBranchIntegrationUpdate(_ status: CurrentBranchIntegrationStatus) {
        runRemoteOperation("Updating \(status.branch)...", remotes: [status.remote]) { credentialResolver in
            guard await waitForBackgroundRemoteActivity() else { return }
            await syncState.performCurrentBranchIntegrationUpdate(
                status: status,
                preferredRemote: repoSettings.defaultRemoteName,
                gitFlowConfiguration: gitFlowConfiguration,
                pullStrategy: repoSettings.pullStrategy,
                repositoryURL: repositoryURL,
                undoManager: undoManager,
                credentialResolver: credentialResolver
            )
            if await GitStatusService.shared.hasConflicts(in: repositoryURL) {
                await MainActor.run {
                    selectedItem = .item(.fileStatus)
                }
            }
        }
    }

    private var tagDetailsSheetPresented: Binding<Bool> {
        Binding(
            get: { displayedTagDetails != nil },
            set: { isPresented in
                if !isPresented {
                    displayedTagDetails = nil
                }
            }
        )
    }

    private var tagDeletionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingTagDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTagDeletion = nil
                }
            }
        )
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(spacing: 0) {
            Color(nsColor: .controlBackgroundColor)
                .frame(height: 1)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.separator)
                        .frame(height: 0.5)
                }

            ZStack {
                cachedRepositoryScreens

                switch selectedItem {
            case .item(.fileStatus):
                EmptyView()
            case .item(.history), .branch, .worktree, .tag, .remoteBranch, .head:
                if let referenceDiffBase, let referenceDiffTarget, let referenceDiffTitle {
                    ReferenceDiffView(
                        repositoryURL: repositoryURL,
                        baseRef: referenceDiffBase,
                        targetRef: referenceDiffTarget,
                        title: referenceDiffTitle,
                        onClose: {
                            isOpeningReferenceDiff = false
                            clearReferenceDiff()
                        }
                    )
                    .id("\(referenceDiffBase)→\(referenceDiffTarget)")
                } else {
                    EmptyView()
                }
            case .item(.reflog):
                EmptyView()
            case .item(.pullRequests):
                EmptyView()
            case .stash(let ref):
                StashView(
                    repositoryURL: repositoryURL,
                    stashRef: ref,
                    isWorkSuspended: activeStashActionCount > 0
                        || (pendingStashRef != nil && pendingStashAction != nil)
                )
            case .submodule(let path):
                SubmoduleDetailPlaceholderView {
                    openWorktreeInNewWindow(
                        at: repositoryURL.appendingPathComponent(path, isDirectory: true)
                    )
                }
            case .subtree:
                EmptyStateView(message: "Select a subtree action from the sidebar")
            case .item(.search):
                SearchView(repositoryURL: repositoryURL)
            case .item(.gitLFS):
                EmptyView()
            case .item(.gitFlow):
                GitFlowDashboardView(
                    configuration: gitFlowConfiguration,
                    currentBranch: gitFlowCurrentBranch,
                    checkpoint: gitFlowFinishCheckpoint,
                    recoveryIssue: gitFlowRecoveryIssue,
                    commandState: gitFlowCommandState,
                    perform: handleGitFlowMenuAction
                )
            case .none:
                EmptyStateView(message: "Select an item from the sidebar")
                }
            }
        }
    }

    @ViewBuilder
    private var cachedRepositoryScreens: some View {
        if selectedItem == .item(.pullRequests) || hasOpenedPullRequests {
            Group {
                switch pullRequestAccessDecision {
                case .allowed:
                    PullRequestListView(
                        controller: pullRequestController,
                        repositoryURL: repositoryURL,
                        accountConnectionErrorMessage: providerAccountController.errorMessage,
                        onReconnectAccount: onOpenConnections,
                        onRequestCreatePullRequest: {
                            prepareCreatePullRequest()
                        },
                        authorizeAction: { await authorizePullRequestAccess() }
                    )
                case .denied(let denial):
                    FeatureAccessUnavailableView(
                        notice: FeatureAccessNotice(feature: .pullRequests, denial: denial),
                        isSignedIn: accountController.account != nil,
                        onAccountAction: presentFeatureAccessAccountAction,
                        onRetry: {
                            Task {
                                _ = await authorizePullRequestAccess(
                                    forceRefresh: true,
                                    presentNotice: false
                                )
                            }
                        }
                    )
                case nil:
                    ProgressView("Checking Pull Request access…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear { hasOpenedPullRequests = true }
            .repositoryScreenVisibility(isActive: selectedItem == .item(.pullRequests))
        }

        if selectedItem == .item(.gitLFS) || hasOpenedGitLFS {
            GitLFSAccessView(repositoryURL: repositoryURL) { authorize in
                GitLFSView(repositoryURL: repositoryURL, initialPath: lfsTrackingPath, credentialResolver: { @MainActor remote in
                    await credentialResolverForRemoteOperation(remotes: [remote])
                }, refreshRepository: {
                    await syncState.refresh(repositoryURL: repositoryURL, force: true)
                }, authorizeAction: authorize)
            }
            .id(repositoryURL)
            .onAppear { hasOpenedGitLFS = true }
            .repositoryScreenVisibility(isActive: selectedItem == .item(.gitLFS))
        }

        FileStatusView(
            repositoryURL: repositoryURL,
            isActive: isFileStatusActive,
            aiProviderController: aiProviderController,
            syncState: syncState,
            undoManager: undoManager,
            preferredRemote: repoSettings.defaultRemoteName,
            gitFlowConfiguration: gitFlowConfiguration,
            canUpdateCurrentBranch: canUpdateCurrentBranch,
            onRequestUpdateCurrentBranch: requestCurrentBranchIntegrationUpdate,
            onRequestApplyStash: { ref in requestStashAction(ref: ref, action: .apply) },
            onRequestComparePath: { pathComparisonWindow.show(path: $0, in: repositoryURL) },
            onRequestTrackLFS: { path in
                lfsTrackingPath = path
                selectedItem = .item(.gitLFS)
            },
            onAuthorizeCommit: authorizeProtectedBranchCommit,
            onRequestPushAfterCommit: pushAfterCommit,
            onRunRepositoryOperation: runRepositoryOperation,
            onCustomActionSelectionChanged: { customActionFilePaths = $0 },
            onRunCustomAction: { id, paths in
                runCustomAction(
                    id: id,
                    context: CustomActionInvocationContext(
                        repositoryURL: repositoryURL,
                        filePaths: paths,
                        commitHashes: []
                    ),
                    surface: .selectedFiles
                )
            },
            onOpenFileInEditor: { path, lineTarget in
                prepareToOpenSearchFile(path, lineTarget: lineTarget)
            }
        )
        .repositoryScreenVisibility(isActive: isFileStatusActive)

        HistoryScreen(
            repositoryURL: repositoryURL,
            isActive: isHistoryActive,
            isWorkSuspended: showingCheckoutConfirmation || pendingRemoteBranchCheckout != nil
                || showingDetachedHeadConfirmation || pendingHistoryCheckout != nil
                || activeTagCheckoutCount > 0,
            selectedBranch: selectedBranchName,
            branchFilter: $appState.historyBranchFilter,
            includeRemotes: $appState.historyIncludeRemotes,
            dependencies: HistoryCommitActionController.Dependencies(
                repositoryURL: repositoryURL,
                undoManager: undoManager,
                syncState: syncState,
                runOperation: runRepositoryOperation,
                requestCheckout: checkoutRequest,
                requestExplain: explainCommitWithRepositoryAI,
                requestBrowseRevision: { revisionBrowserWindow.show(revision: $0.hash, in: repositoryURL, credentialResolver: providerCredentialResolver) },
                runCustomAction: { id, hashes in
                    runCustomAction(
                        id: id,
                        context: CustomActionInvocationContext(
                            repositoryURL: repositoryURL,
                            filePaths: [],
                            commitHashes: hashes
                        ),
                        surface: .selectedCommits
                    )
                },
                headHash: { nil }
            ),
            selectionSink: historySelectionSink,
            onOpenFile: { path, lineTarget in
                prepareToOpenSearchFile(path, lineTarget: lineTarget)
            }
        )
        .id(repositoryURL)
        .repositoryScreenVisibility(isActive: isHistoryActive)

        ReflogView(
            repositoryURL: repositoryURL,
            isActive: isReflogActive,
            onShowCommit: { hash in
                appState.historyBranchFilter = .branch(hash)
                selectedItem = .branch(hash)
            },
            onCreateBranch: { entry in
                presentBranchSheet(startPoint: .commit(hash: entry.hash, message: entry.message))
            }
        )
        .repositoryScreenVisibility(isActive: isReflogActive)
    }

    private var isFileStatusActive: Bool { selectedItem == .item(.fileStatus) }
    private var isReflogActive: Bool { selectedItem == .item(.reflog) }
    private func revealWorktreeInHistory(_ worktreeURL: URL) {
        Task {
            let reference = await GitStatusService.shared.worktreeHistoryReference(for: worktreeURL, in: repositoryURL)
            await MainActor.run {
                guard selectedItem == .worktree(worktreeURL) else { return }
                selectedBranchName = reference
            }
        }
    }

    private var isHistoryActive: Bool {
        guard referenceDiffBase == nil else { return false }
        return switch selectedItem {
        case .item(.history), .branch, .worktree, .tag, .remoteBranch, .head: true
        default: false
        }
    }

    private var pullRequestAccessTaskID: String {
        let accounts = providerAccountController.accounts.map {
            "\($0.id)-\(String(describing: $0.tokenStatus))"
        }.joined(separator: ",")
        return [
            String(describing: selectedItem),
            String(featureAccessController.policy.revision),
            String(describing: featureAccessController.policy.rule(for: .pullRequests)),
            accountController.entitlement.plan.rawValue,
            accountController.entitlement.access.rawValue,
            accounts,
        ].joined(separator: "|")
    }

    private func presentFeatureAccessAccountAction() {
        if accountController.account == nil {
            accountController.presentAuthentication(.signIn)
        } else {
            proUpgradeErrorMessage = nil
            proUpgradePresentation = ProUpgradePresentation(feature: .pullRequests)
        }
    }

    private func featureAccessAlert(for notice: FeatureAccessNotice) -> Alert {
        let isSignedIn = accountController.account != nil
        let title = Text(notice.title(isSignedIn: isSignedIn))
        let message = Text(notice.message(isSignedIn: isSignedIn))
        if notice.denial == .requiresPro {
            return Alert(
                title: title,
                message: message,
                primaryButton: .default(
                    Text(isSignedIn ? "View Pricing" : "Sign In"),
                    action: presentFeatureAccessAccountAction
                ),
                secondaryButton: .cancel()
            )
        }
        if notice.denial == .repositoryVisibilityUnavailable {
            return Alert(
                title: title,
                message: message,
                primaryButton: .default(Text("Try Again")) {
                    retryFeatureAccess(for: notice.feature)
                },
                secondaryButton: .cancel()
            )
        }
        return Alert(title: title, message: message, dismissButton: .default(Text("OK")))
    }

    private func retryFeatureAccess(for feature: PlanFeature) {
        switch feature {
        case .pullRequests:
            Task {
                _ = await authorizePullRequestAccess(forceRefresh: true)
            }
        case .gitFlow:
            Task {
                _ = await authorizeGitFlowAccess(forceRefresh: true)
            }
        case .privateRepositories, .gitLFS, .aiCommitMessage, .repositoryChat, .repositoryAIActions,
             .aiConflictResolution, .aiBringYourOwnKey, .multipleProviderAccounts, .branchMergeDetection:
            break
        }
    }

    private func dismissProUpgradeSheet() {
        guard accountController.openingWebDestination != .pricing else { return }
        proUpgradePresentation = nil
        proUpgradeErrorMessage = nil
    }

    private func performProUpgradePrimaryAction() {
        guard accountController.openingWebDestination != .pricing else { return }
        proUpgradeErrorMessage = nil

        guard accountController.account != nil else {
            proUpgradePresentation = nil
            Task {
                await Task.yield()
                accountController.presentAuthentication(.signIn)
            }
            return
        }

        Task {
            await accountController.openPricingOnWeb()
            if let errorMessage = accountController.errorMessage {
                proUpgradeErrorMessage = errorMessage
            } else {
                proUpgradePresentation = nil
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            leftToolbar
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                RepositoryActivityHeaderButton(
                    operationProgress: operationProgress,
                    repositoryName: repositoryURL.lastPathComponent,
                    providerIconName: repoIconName,
                    textScale: appState.textSize.scale,
                    syncActivity: syncState.currentSyncActivity,
                    lastFetchSucceeded: syncState.lastFetchSucceeded,
                    isAutomaticFetching: syncState.isAutomaticFetching
                ) { item in
                    backgroundErrorDetail = item
                }
                GitHubNotificationBell()
            }
            .padding(.leading, 12)
        }

        ToolbarSpacer(.flexible)

        if windowWidth >= Self.pinnedToolbarShortcutsMinimumWindowWidth,
           !appState.pinnedRepositoryToolbarShortcuts.isEmpty {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 2) {
                    ForEach(appState.pinnedRepositoryToolbarShortcuts) { shortcut in
                        toolbarButton(
                            icon: shortcut.systemImage,
                            label: shortcut.title,
                            showText: appState.showToolbarButtonText,
                            disabled: isRepositoryToolbarShortcutDisabled(shortcut),
                            action: { performRepositoryToolbarShortcut(shortcut) }
                        )
                    }
                }
                .controlSize(.large)
                // .padding(.horizontal, -6)
            }

            ToolbarSpacer(.fixed)
        }

        ToolbarItem(placement: .automatic) {
            Button("Toolbar shortcuts", systemImage: "square.grid.2x2") {
                showingToolbarShortcutPopover.toggle()
            }
            .controlSize(.large)
            .labelStyle(.iconOnly)
            .padding(.leading, 6)
            .padding(.vertical, 1)
            .help("Toolbar Shortcuts")
            .popover(isPresented: $showingToolbarShortcutPopover) {
                RepositoryToolbarShortcutPopover(
                    pinnedShortcuts: appState.pinnedRepositoryToolbarShortcuts,
                    isActionDisabled: isRepositoryToolbarShortcutDisabled,
                    onPerformAction: performRepositoryToolbarShortcut,
                    onSetPinned: { shortcut, isPinned in
                        appState.setRepositoryToolbarShortcut(shortcut, isPinned: isPinned)
                    }
                )
            }
        }

        ToolbarItem(placement: .automatic) {
            Button("Repository AI Chat", systemImage: "sidebar.right") {
                showingRepositoryAIChatPanel.toggle()
            }
            .controlSize(.large)
            .labelStyle(.iconOnly)
            .padding(.trailing, 6)
            .padding(.vertical, 1)
            .help(showingRepositoryAIChatPanel ? "Hide Repository AI Chat" : "Show Repository AI Chat")
        }
    }

    private func requestRepositoryChatAccess() {
        guard accountController.account != nil else {
            accountController.presentAuthentication(.signIn)
            return
        }

        switch featureAccessController.decision(
            for: .repositoryChat,
            entitlement: accountController.entitlement
        ) {
        case .allowed:
            break
        case .denied(.requiresPro):
            proUpgradeErrorMessage = nil
            proUpgradePresentation = ProUpgradePresentation(feature: .repositoryChat)
        case .denied(let denial):
            featureAccessNotice = FeatureAccessNotice(feature: .repositoryChat, denial: denial)
        }
    }

    private var repositoryAIChatPanelWidthBinding: Binding<CGFloat> {
        Binding(
            get: {
                RepositoryToolbarShortcutPanel.clampedWidth(
                    CGFloat(storedRepositoryAIChatPanelWidth)
                )
            },
            set: { width in
                storedRepositoryAIChatPanelWidth = Double(
                    RepositoryToolbarShortcutPanel.clampedWidth(width)
                )
            }
        )
    }

    private func explainCommitWithRepositoryAI(_ commit: Commit) {
        showingRepositoryAIChatPanel = true

        let accessDecision = featureAccessController.decision(
            for: .repositoryChat,
            entitlement: accountController.entitlement
        )
        guard accessDecision.isAllowed else {
            requestRepositoryChatAccess()
            return
        }

        repositoryAIChatController.startNewConversation()
        Task {
            await repositoryAIChatController.explainCommit(
                RepositoryAICommitChoice(hash: commit.hash, subject: commit.message)
            )
        }
    }

    private func isRepositoryToolbarShortcutDisabled(
        _ shortcut: RepositoryToolbarShortcut
    ) -> Bool {
        if operationProgress.activeOperation != nil {
            return true
        }

        return switch shortcut {
        case .undo:
            GitUndoToolbarPolicy.isUndoDisabled(
                isSyncing: syncState.isAnySyncing,
                canUndo: undoManager.canUndo
            )
        case .remote:
            remoteURLString.isEmpty
        case .finder, .editor, .terminal, .settings:
            false
        }
    }

    func presentRepositorySettingsWindow() {
        showingRepositorySettings = true
        repositorySettingsWindow.show(
            content: repositorySettingsSheet.environmentObject(appState),
            onClose: {
                showingRepositorySettings = false
                initiallySelectGitFlowSettings = false
            }
        )
    }

    private func performRepositoryToolbarShortcut(_ shortcut: RepositoryToolbarShortcut) {
        guard !isRepositoryToolbarShortcutDisabled(shortcut) else { return }
        showingToolbarShortcutPopover = false

        switch shortcut {
        case .undo:
            handleGitUndoMenuAction(.undo)
        case .remote:
            openRemoteURL()
        case .finder:
            showInFinder()
        case .editor:
            openRepositoryInExternalEditor()
        case .terminal:
            openTerminal()
        case .settings:
            initiallySelectGitFlowSettings = false
            presentRepositorySettingsWindow()
        }
    }

    private func performInitialLoad() async {
        async let loadedRemotes = GitStatusService.shared.remotes(in: repositoryURL)
        async let loadedCurrentBranch = GitStatusService.shared.currentBranch(in: repositoryURL)
        async let loadedLocalBranches = GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
        async let loadedGitFlowConfiguration = gitFlowConfigurationStore.loadResult(in: repositoryURL)
        async let loadedGitFlowCheckpoint = GitFlowRecoveryStore().loadResult(in: repositoryURL)
        async let loadedGitCommonDirectory = try? GitStatusService.shared.gitCommonDirectory(in: repositoryURL)
        async let loadedMainWorktreePath = GitStatusService.shared.mainWorktreePath(in: repositoryURL)
        let (remotes, currentBranch, localBranches, configurationResult, checkpointResult, gitCommonDirectory, mainWorktreePath) = await (
            loadedRemotes,
            loadedCurrentBranch,
            loadedLocalBranches,
            loadedGitFlowConfiguration,
            loadedGitFlowCheckpoint,
            loadedGitCommonDirectory,
            loadedMainWorktreePath
        )
        let loadedSettings = await repoSettingsStore.settings(
            for: repositoryURL.path,
            mainWorktreePath: mainWorktreePath?.path,
            currentBranch: currentBranch,
            remotes: remotes
        )
        await MainActor.run {
            repoSettings = loadedSettings
            gitFlowCurrentBranch = currentBranch ?? ""
            switch configurationResult {
            case .none:
                gitFlowConfiguration = GitFlowConfiguration.detected(branches: localBranches)
                gitFlowConfigurationIssue = nil
            case .value(let configuration):
                gitFlowConfiguration = configuration
                gitFlowConfigurationIssue = nil
            case .invalid(let issue):
                gitFlowConfiguration = GitFlowConfiguration.detected(branches: localBranches)
                gitFlowConfigurationIssue = issue
                syncState.showError("The saved Git Flow configuration is invalid. Open Repository Settings and save a valid configuration to replace it.")
            }
            switch checkpointResult {
            case .none:
                gitFlowFinishCheckpoint = nil
                gitFlowRecoveryIssue = nil
            case .value(let checkpoint):
                gitFlowFinishCheckpoint = checkpoint
                gitFlowRecoveryIssue = nil
            case .invalid(let issue):
                gitFlowFinishCheckpoint = nil
                gitFlowRecoveryIssue = issue
                syncState.showError(issue.message)
            }
            gitFlowWorktreeRootURL = gitCommonDirectory?.deletingLastPathComponent()
        }
        await refreshRemotePresentation(for: loadedSettings.defaultRemoteName)
        await syncState.refresh(repositoryURL: repositoryURL)
        var didFetchRemoteRefs = false
        if loadedSettings.resolvedRefreshOnAppActive(
            globalValue: appState.refreshOnAppActive
        ), let credentialResolver = await credentialResolverForFetch(
            options: GitStatusService.FetchOptions()
        ) {
            didFetchRemoteRefs = await syncState.performAutomaticFetch(
                options: GitStatusService.FetchOptions(),
                repositoryURL: repositoryURL,
                credentialResolver: credentialResolver,
                force: true
            )
        }
        if didFetchRemoteRefs {
            await syncState.refresh(repositoryURL: repositoryURL)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .repositoryRemoteRefsDidRefresh,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        }
        await MainActor.run {
            didPerformInitialLoad = true
        }
        startBackgroundSyncIfLoaded(settings: loadedSettings)

        await MainActor.run {
            if initialShowsHistory == nil,
               syncState.commitBadgeCount == 0,
               syncState.inProgressOperation == nil,
               selectedItem == .item(.fileStatus) {
                selectedItem = .item(.history)
            }
        }
    }

    private var gitFlowConfigurationSyncTaskID: String {
        "\(didPerformInitialLoad)|\(accountController.account?.uid ?? "signed-out")"
    }

    /// The only entry point for starting background polling. Polling keeps running while the app
    /// is inactive (e.g. visible on a second display) and waits for the initial load so it never
    /// runs with placeholder settings.
    func startBackgroundSyncIfLoaded(
        settings: RepoSettings? = nil,
        globalAutoFetchEnabled: Bool? = nil,
        defersInitialWork: Bool = false
    ) {
        guard didPerformInitialLoad else {
            syncState.stopBackgroundSync()
            return
        }
        syncState.startBackgroundSync(
            repositoryURL: repositoryURL,
            settings: settings ?? repoSettings,
            globalAutoFetchEnabled: globalAutoFetchEnabled ?? appState.autoFetchEnabled,
            defersInitialWork: defersInitialWork
        )
    }

    private func reconcileGitFlowConfigurationWithCloud() async {
        guard didPerformInitialLoad else { return }
        let outcome = await gitFlowConfigurationSyncController.reconcile(
            repositoryURL: repositoryURL,
            fallbackConfiguration: gitFlowConfiguration,
            uid: accountController.account?.uid
        )
        if let configuration = outcome.configuration {
            gitFlowConfiguration = configuration
            gitFlowConfigurationIssue = nil
        }
        if let warningMessage = outcome.warningMessage {
            syncState.showError(warningMessage)
        }
    }

    private var leftToolbar: some View {
        let syncing = syncState.isAnySyncing
        let operationInProgress = operationProgress.activeOperation != nil
        let showText = appState.showToolbarButtonText
        return HStack(spacing: 2) {
            BadgeToolbarButton(icon: "plus", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: operationInProgress, showText: showText, action: { showCommitSheetIfNoConflicts() })
            BadgeToolbarButton(icon: "arrow.down.to.line", label: "Pull", badgeCount: syncState.pullBadgeCount, isLoading: syncState.isPulling, disabled: syncing || operationInProgress, showText: showText, action: { showingPullSheet = true })
            BadgeToolbarButton(icon: "arrow.up.to.line", label: "Push", badgeCount: syncState.pushBadgeCount, isLoading: syncState.isPushing, disabled: syncing || operationInProgress, showText: showText, action: { showingPushSheet = true })
            toolbarButton(icon: "arrow.down.circle", label: "Fetch", showText: showText, isLoading: syncState.isFetching, disabled: syncing || operationInProgress, action: { showingFetchSheet = true })
            if appState.showHeaderBranchButton {
                toolbarButton(icon: "arrow.triangle.branch", label: "Branch", showText: showText, disabled: operationInProgress, action: { presentBranchSheet(startPoint: nil) })
            }
            if appState.showHeaderMergeButton {
                toolbarButton(icon: "arrow.triangle.merge", label: "Merge", showText: showText, isLoading: syncState.isMerging, disabled: syncing || operationInProgress, action: { showingMergeSheet = true })
            }
            if appState.showHeaderStashButton {
                toolbarButton(icon: "archivebox", label: "Stash", showText: showText, isLoading: syncState.isStashing, disabled: syncing || operationInProgress || syncState.stashableCount == 0, action: { showingStashSheet = true })
            }
            if appState.showHeaderTagButton {
                toolbarButton(icon: "tag", label: "Tag", showText: showText, disabled: syncing || operationInProgress, action: { showingNewTagSheet = true })
            }
        }
    }

    func showCommitSheetIfNoConflicts() {
        guard !syncState.isAnySyncing else {
            syncState.showInfo("Wait for the current Git operation to finish before committing.")
            return
        }
        Task {
            if await syncState.checkConflicts(repositoryURL: repositoryURL) { return }
            guard !Task.isCancelled, !syncState.isAnySyncing else { return }
            showingCommitSheet = true
        }
    }

    func commitFromToolbar(message: String, commitAllChanges: Bool) async throws -> Bool {
        guard !syncState.isAnySyncing else {
            throw GitError.commandFailed("Wait for the current Git operation to finish before committing.")
        }
        guard !(await GitStatusService.shared.hasConflicts(in: repositoryURL)) else {
            throw GitError.commandFailed("There are unresolved merge conflicts. Please resolve them before committing.")
        }
        guard await authorizeProtectedBranchCommit() else { return false }
        var failureMessage: String?
        let succeeded = await syncState.performCommit(
            message: message, repositoryURL: repositoryURL, undoManager: undoManager,
            commitAllChanges: commitAllChanges, onError: { failureMessage = $0 }
        )
        guard succeeded else {
            throw GitError.commandFailed(failureMessage ?? "Could not commit changes.")
        }
        toolbarCommitMessage = ""
        return true
    }

    func performCommitDropCherryPick(_ confirmation: PendingCommitDropConfirmation) async {
        guard !syncState.isAnySyncing else {
            await MainActor.run {
                syncState.showInfo("Wait for the current Git operation to finish before dragging commits.")
            }
            return
        }

        let hashes = confirmation.commits.map(\.hash)
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        guard currentBranch == confirmation.targetBranch else {
            await MainActor.run {
                syncState.showInfo("The HEAD branch changed. Repeat the drag and drop action.")
            }
            return
        }

        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.cherryPickCommits(hashes, in: repositoryURL)
            await registerHeadChangingUndo(
                label: hashes.count == 1 ? "Cherry-pick \(confirmation.commits[0].hash.prefix(7))" : "Cherry-pick \(hashes.count) commits",
                oldHead: oldHead,
                redoOperation: .cherryPickCommits(commits: hashes)
            )
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await syncState.refresh(repositoryURL: repositoryURL)
            let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
            let inProgress = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
            await MainActor.run {
                if hasConflicts {
                    selectedItem = .item(.fileStatus)
                    syncState.showError("Cherry-pick produced conflicts. Resolve them in the File status view, then continue or abort.")
                } else if inProgress != nil {
                    selectedItem = .item(.fileStatus)
                    syncState.showError("Cherry-pick produced an empty commit. Open the File status view to skip or abort.")
                } else {
                    syncState.showError(error.localizedDescription)
                }
            }
        }
    }

    func performBranchDropOperation(_ confirmation: PendingBranchDropConfirmation) async {
        guard !syncState.isAnySyncing, !isPerformingBranchDropOperation else {
            await MainActor.run {
                syncState.showInfo("Wait for the current Git operation to finish before dragging branches.")
            }
            return
        }

        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        guard currentBranch == confirmation.targetBranch else {
            await MainActor.run {
                syncState.showInfo("The current branch changed. Repeat the drag and drop action.")
            }
            return
        }

        guard confirmation.sourceBranch != confirmation.targetBranch else {
            await MainActor.run {
                syncState.showInfo("Drop a different branch onto the current branch.")
            }
            return
        }

        if await GitStatusService.shared.hasConflicts(in: repositoryURL) {
            await MainActor.run {
                selectedItem = .item(.fileStatus)
                syncState.showConflict("There are unresolved merge conflicts. Please resolve them before proceeding.")
            }
            return
        }

        let inProgressOperation = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
        guard inProgressOperation == nil else {
            await MainActor.run {
                syncState.showInfo("Finish the current Git operation before dragging branches.")
            }
            return
        }

        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)

        await MainActor.run {
            isPerformingBranchDropOperation = true
        }
        defer {
            Task { @MainActor in
                isPerformingBranchDropOperation = false
            }
        }

        do {
            switch confirmation.operation {
            case .merge:
                try await GitStatusService.shared.mergeCommit(
                    confirmation.sourceBranch,
                    noCommit: false,
                    log: false,
                    in: repositoryURL
                )
            case .rebase:
                try await GitStatusService.shared.rebaseCommit(
                    confirmation.sourceBranch,
                    in: repositoryURL
                )
            }

            await registerHeadChangingUndo(
                label: confirmation.operation == .merge
                    ? "Merge \(confirmation.sourceBranch)"
                    : "Rebase onto \(confirmation.sourceBranch)",
                oldHead: oldHead,
                redoOperation: confirmation.operation == .merge
                    ? .mergeCommit(commit: confirmation.sourceBranch, noCommit: false, log: false)
                    : .rebaseOnto(commit: confirmation.sourceBranch)
            )
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )

            let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
            let inProgressAfterFailure = await GitStatusService.shared.inProgressOperation(in: repositoryURL)

            await MainActor.run {
                if hasConflicts || inProgressAfterFailure != nil {
                    selectedItem = .item(.fileStatus)
                    syncState.showConflict(
                        confirmation.operation == .merge
                            ? "Merge conflicts occurred during Merge. Please resolve them in the File status view."
                            : "Rebase conflicts occurred during Rebase. Please resolve them in the File status view."
                    )
                } else {
                    syncState.showError(error.localizedDescription)
                }
            }
        }
    }

    private func registerHeadChangingUndo(
        label: String,
        oldHead: String?,
        redoOperation: GitUndoOperation
    ) async {
        guard let oldHead,
              let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
              oldHead != newHead else { return }

        await MainActor.run {
            undoManager.register(
                GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: label,
                    undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                    redoOperation: redoOperation
                )
            )
        }
    }

    func requestStashAction(ref: String, action: StashAction) {
        if action == .delete && !repoSettings.confirmDestructiveStashActions {
            Task {
                await performStashAction(ref: ref, action: action, deleteAfterApplying: false)
            }
            return
        }
        pendingStashRef = ref
        pendingStashAction = action
    }

    private var stashActionSheetBinding: Binding<Bool> {
        Binding(
            get: { pendingStashRef != nil && pendingStashAction != nil },
            set: { isPresented in
                if !isPresented {
                    clearPendingStashAction()
                }
            }
        )
    }

    @MainActor
    private func clearPendingStashAction() {
        pendingStashRef = nil
        pendingStashAction = nil
    }

    func performStashAction(ref: String, action: StashAction, deleteAfterApplying: Bool) async {
        activeStashActionCount += 1
        defer { activeStashActionCount -= 1 }
        do {
            switch action {
            case .apply:
                let support = GitStashUndoSupport()
                let canRegisterUndo = await canRegisterStashApplyUndo(ref: ref)
                let head = canRegisterUndo ? await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL) : nil
                let hash = canRegisterUndo ? try await support.hash(for: ref, in: repositoryURL) : nil
                let summary = canRegisterUndo ? try await support.summary(for: ref, in: repositoryURL) : nil
                try await GitStatusService.shared.applyStash(
                    ref: ref,
                    dropAfterApplying: deleteAfterApplying,
                    in: repositoryURL
                )
                if canRegisterUndo, let head, let hash, let summary {
                    let undoOperation: GitUndoOperation
                    if deleteAfterApplying {
                        undoOperation = .sequence([
                            .resetHardToHead(expectedHead: head),
                            .stashStore(commit: hash, message: summary)
                        ])
                    } else {
                        undoOperation = .resetHardToHead(expectedHead: head)
                    }
                    await MainActor.run {
                        undoManager.register(
                            GitUndoEntry(
                                repositoryURL: repositoryURL,
                                label: deleteAfterApplying ? "Pop stash" : "Apply stash",
                                undoOperation: undoOperation,
                                redoOperation: deleteAfterApplying ? .stashPop(ref: ref) : .stashApply(ref: hash)
                            )
                        )
                    }
                }
            case .delete:
                let support = GitStashUndoSupport()
                let hash = try await support.hash(for: ref, in: repositoryURL)
                let summary = try await support.summary(for: ref, in: repositoryURL)
                try await GitStatusService.shared.dropStash(ref: ref, in: repositoryURL)
                await MainActor.run {
                    undoManager.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Drop stash",
                            undoOperation: .stashStore(commit: hash, message: summary),
                            redoOperation: .stashDropMatchingHash(hash: hash)
                        )
                    )
                }
            }
        } catch {
            syncState.showError(error.localizedDescription)
        }

        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )

        await MainActor.run {
            clearPendingStashAction()
        }
    }

    private func canRegisterStashApplyUndo(ref: String) async -> Bool {
        let support = GitStashUndoSupport()
        do {
            let clean = try await support.isWorkingTreeClean(in: repositoryURL)
            let hasUntrackedPayload = try await support.stashHasUntrackedPayload(ref: ref, in: repositoryURL)
            if !clean || hasUntrackedPayload {
                await MainActor.run {
                    syncState.showInfo("Stash action completed without undo because the working tree or stash payload is not clean enough for a safe reset.")
                }
                return false
            }
            return true
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
            return false
        }
    }

    func openRemoteURL(remote: String? = nil) {
        if let remote {
            Task {
                let remoteValue = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
                guard let url = browserURL(from: remoteValue) else {
                    _ = await MainActor.run {
                        syncState.showInfo("Could not find a remote URL for '\(remote)'.")
                    }
                    return
                }
                _ = await MainActor.run {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        guard let url = browserURL(from: remoteURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    func showInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repositoryURL.path)
    }

    func openRepositoryInExternalEditor() {
        let applications = IntegrationApplicationCatalog.availableApplications(for: .editor)

        if let preferredBundleIdentifier =
                appState.preferredSearchFileApplicationBundleIdentifier,
           let preferredApplication = applications.first(where: {
               $0.bundleIdentifier == preferredBundleIdentifier
           }) {
            launchRepository(in: preferredApplication)
            return
        }

        if appState.preferredSearchFileApplicationBundleIdentifier != nil {
            appState.preferredSearchFileApplicationBundleIdentifier = nil
        }

        guard !applications.isEmpty else {
            syncState.showError("No supported external editor is installed.")
            return
        }

        externalEditorApplications = applications
        showingExternalEditorChooser = true
    }

    private func launchRepository(in application: IntegrationApplication) {
        Task { @MainActor in
            do {
                try await IntegrationApplicationLauncher.launch(
                    application,
                    opening: repositoryURL
                )
            } catch {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func openTerminal() {
        openTerminal(at: repositoryURL)
    }

    func openWorktreeInNewWindow(at path: URL) {
        openWindow(
            id: "main",
            value: RepositoryWindowRequest.repository(
                path,
                shouldFitVisibleScreen: false
            )
        )
    }

    private func openWorktreeInTerminal(at path: URL) {
        openTerminal(at: path)
    }

    private func openTerminal(at directoryURL: URL) {
        Task { @MainActor in
            do {
                try await IntegrationSettingsStore.shared.openTerminal(at: directoryURL)
            } catch {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func openGitIgnoreFile() {
        do {
            let fileURL = try fileService.prepareGitIgnore(in: repositoryURL)
            NSWorkspace.shared.open(fileURL)
        } catch {
            syncState.showError(error.localizedDescription)
        }
    }

    func openGitConfigFile() {
        guard let fileURL = fileService.gitConfigURL(in: repositoryURL) else {
            syncState.showInfo("Could not find .git/config for this repository.")
            return
        }
        NSWorkspace.shared.open(fileURL)
    }

    func refreshRemotePresentation(for preferredRemote: String?) async {
        let remote: String?
        if let preferredRemote {
            remote = preferredRemote
        } else {
            remote = RepoSettings.preferredRemote(in: await GitStatusService.shared.remotes(in: repositoryURL))
        }
        guard let remote else {
            await MainActor.run {
                remoteURLString = ""
                repoIconName = "code-branch"
            }
            return
        }

        let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        await MainActor.run {
            remoteURLString = remoteURL
            repoIconName = remoteURL.isEmpty ? "code-branch" : determineRepoIconName(from: remoteURL)
        }
    }

    func resolvedPullPreselectedBranch() -> String? {
        if repoSettings.defaultPullBranch.isEmpty {
            return pullPreselectedBranch
        }
        return repoSettings.defaultPullBranch
    }

    func presentTagSheetFromBranchTip(_ sourceBranch: String) {
        presentTagSheet(startPoint: TagStartPoint(
            hash: "refs/heads/" + sourceBranch, message: sourceBranch, isBranch: true
        ))
    }

    func presentTagSheetFromCommit(_ commit: GitDraggedCommit) {
        presentTagSheet(
            startPoint: TagStartPoint(
                hash: commit.hash,
                message: commit.message
            )
        )
    }

    private func presentTagSheet(startPoint: TagStartPoint) {
        tagStartPoint = startPoint
        showingTagSheet = true
    }

    func presentTagMoveConfirmation(tagName: String, commit: GitDraggedCommit) {
        guard !syncState.isAnySyncing else {
            syncState.showInfo("Wait for the current Git operation to finish before moving a tag.")
            return
        }
        pendingTagMoveConfirmation = RepositorySheetRequest(input: (tag: tagName, commit: commit))
    }

    func loadTagMoveConfirmation(tagName: String, commit: GitDraggedCommit) async throws -> PendingTagMoveConfirmation {
        async let details = GitStatusService.shared.tagDetails(name: tagName, in: repositoryURL)
        async let remotes = GitStatusService.shared.remotes(in: repositoryURL)
        let (currentCommit, remoteNames) = try await (details, remotes)
        try Task.checkCancellation()
        guard currentCommit.commitHash != commit.hash else {
            throw GitError.commandFailed("Tag \(tagName) already points to this commit.")
        }
        return PendingTagMoveConfirmation(
            tagName: tagName, currentCommit: currentCommit,
            newCommit: commit, remotes: remoteNames.sorted()
        )
    }

    func performTagMove(
        _ confirmation: PendingTagMoveConfirmation,
        forcePushRemote: String?
    ) async throws {
        do {
            try await GitStatusService.shared.moveTag(
                name: confirmation.tagName,
                commit: confirmation.newCommit.hash,
                in: repositoryURL
            )

            if let remote = forcePushRemote {
                _ = try await GitStatusService.shared.push(
                    options: GitStatusService.PushOptions(
                        remote: remote,
                        tags: [confirmation.tagName],
                        forceTags: true
                    ),
                    in: repositoryURL,
                    credentialResolver: providerCredentialResolver
                )
            }

        } catch {
            refreshAfterTagAction()
            throw error
        }
    }

    func createTagAtReference(name: String, startPoint: TagStartPoint) async throws {
        let reference: String
        if startPoint.isBranch {
            guard let hash = await GitStatusService.shared.tipHash(for: startPoint.hash, in: repositoryURL) else {
                throw GitError.commandFailed("Could not find the last commit for \(startPoint.message).")
            }
            reference = hash
        } else {
            reference = startPoint.hash
        }
        try await GitStatusService.shared.createTag(
            name: name, commit: reference, annotated: false, message: nil, in: repositoryURL
        )
    }

    func createTag(from request: TagCreationRequest) async throws {
        try await GitStatusService.shared.createTag(
            name: request.name,
            commit: request.commitReference,
            annotated: false,
            message: nil,
            in: repositoryURL
        )

        if let remote = request.pushRemote {
            _ = try await GitStatusService.shared.push(
                options: GitStatusService.PushOptions(remote: remote, tags: [request.name]),
                in: repositoryURL,
                credentialResolver: providerCredentialResolver
            )
        }

        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }

    private func presentTagDetails(_ tag: String) {
        displayedTagDetails = RepositorySheetRequest(input: tag)
    }

    func deleteTag(_ tag: String, remote: String? = nil) async throws {
        let credentialResolver: GitProviderCredentialResolver?
        if let remote, !remote.isEmpty {
            guard let resolver = await credentialResolverForRemoteOperation(remotes: [remote]) else {
                throw GitError.commandFailed("Account selection was cancelled.")
            }
            credentialResolver = resolver
        } else {
            credentialResolver = nil
        }
        do {
            try await GitStatusService.shared.deleteTag(name: tag, in: repositoryURL)
            if let remote, !remote.isEmpty {
                try await GitStatusService.shared.deleteRemoteTag(
                    name: tag, remote: remote, in: repositoryURL, credentialResolver: credentialResolver
                )
            }
            if selectedItem == .tag(tag) { selectedItem = .item(.history) }
        } catch {
            refreshAfterTagAction()
            throw error
        }
    }

    func refreshAfterTagAction() {
        Task {
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(name: .repositoryDidChange, object: nil,
                                            userInfo: ["repositoryURL": repositoryURL])
        }
    }

    private func resetTagSheet() {
        tagNameInput = ""
        tagStartPoint = nil
    }

}
