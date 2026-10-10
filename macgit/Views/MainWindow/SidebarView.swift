//
//  SidebarView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
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

struct SidebarView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject private var appUpdateController: AppUpdateController
    @EnvironmentObject private var accountController: AccountSessionController
    @EnvironmentObject var appState: AppState

    let repositoryURL: URL
    @Binding var selection: SidebarSelection?
    let undoManager: GitUndoManager?
    let currentBranchFallbackSyncStatus: BranchSyncStatus?
    let defaultRemoteName: String?
    let isAccountMenuDisabled: Bool
    let gitFlowConfiguration: GitFlowConfiguration
    let gitFlowFinishCheckpoint: GitFlowFinishCheckpoint?
    let gitFlowRecoveryIssue: GitFlowLocalStateIssue?
    let isGitFlowOperationDisabled: Bool
    let isBranchSyncing: (String) -> Bool
    let activeSyncBranchName: String?
    let canUpdateCurrentBranch: Bool
    let onRequestCheckout: (String, Bool) -> Void
    let onRequestRemoteBranchCheckout: (RemoteBranchCheckoutTarget) -> Void
    let onRequestFetchBranch: (String) -> Void
    let onRequestPullRemoteBranch: (String, String) -> Void
    let onRequestPullTracked: (String) -> Void
    let onRequestPushToTracked: (String) -> Void
    let onRequestForcePushToTracked: (String) -> Void
    let onRequestForcePushBranchToRemote: (String, String) -> Void
    let onRequestUpdateCurrentBranch: (CurrentBranchIntegrationStatus) -> Void
    let onRequestRenameBranch: (String) -> Void
    let onRequestCreatePullRequest: (String) -> Void
    let onRequestCreateBranchFromBranch: (String) -> Void
    let onRequestCreateTagFromBranch: (String) -> Void
    let onRequestTagDetails: (String) -> Void
    let onRequestDiffTagAgainstCurrent: (String) -> Void
    let onRequestCompareBranches: (String, String) -> Void
    let onRequestPushTagToRemote: (String, String) -> Void
    let onRequestForcePushTagToRemote: (String, String) -> Void
    let onRequestDeleteTag: (String) -> Void
    let onRequestRebaseOnto: (String) -> Void
    let onRequestMergeBranchIntoCurrent: (String) -> Void
    let onRequestPushBranchToRemote: (String, String) -> Void
    let onRequestTrackRemoteBranch: (String, String?) -> Void
    let onRequestCreatePullRequestForRemote: (String, String) -> Void
    let onRequestApplyStash: (String) -> Void
    let onRequestDeleteStash: (String) -> Void
    let onRequestOpenWorktree: (URL) -> Void
    let onRequestOpenWorktreeInTerminal: (URL) -> Void
    let onRequestOpenSubmodule: (URL) -> Void
    let onRequestShowSubmoduleInFinder: (URL) -> Void
    let onRequestOpenSubmoduleInTerminal: (URL) -> Void
    let onRequestAddSubmodule: () -> Void
    let onRequestAddLinkSubtree: () -> Void
    let onRequestCreateBranch: () -> Void
    let onRequestCreateTag: () -> Void
    let onRequestCreatePullRequestFromWorkspace: () -> Void
    let onRequestShowSubtreeInFinder: (URL) -> Void
    let onRequestOpenSubtreeInTerminal: (URL) -> Void
    let onRequestPullSubtree: (GitSubtreeEntry) -> Void
    let onRequestPushSubtree: (GitSubtreeEntry) -> Void
    let onRequestUpdateSubtreeLink: @MainActor (GitSubtreeEntry) async throws -> Void
    let onRequestUnlinkSubtree: @MainActor (GitSubtreeEntry) async throws -> Void
    let onRequestInitializeSubmodule: (String) -> Void
    let onRequestUpdateSubmodule: (String, SubmoduleUpdateMode) -> Void
    let onRequestSynchronizeSubmoduleURL: (String) -> Void
    let onRequestUpdateSubmoduleSettings: @MainActor (String, String, String?) async throws -> Void
    let onRequestDeinitializeSubmodule: @MainActor (String, Bool) async throws -> Void
    let onRequestRemoveSubmodule: @MainActor (String, Bool) async throws -> Void
    let onRequestSearch: () -> Void
    let onRequestStartGitFlow: (GitFlowTopicKind) -> Void
    let onRequestFinishGitFlow: (GitFlowTopicKind) -> Void
    let onRequestResumeGitFlowFinish: () -> Void
    let onRequestAbortGitFlowFinish: () -> Void
    let onRequestEditGitFlow: () -> Void
    let onRequestDisableGitFlow: () -> Void
    let onRequestDragDrop: (GitDragDropRequest) -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State var branchNodes: [BranchNode] = []
    @State var sidebarDataRepositoryURL: URL?
    @State var cachedVisibleBranchRows: [BranchRowItem] = []
    @State var currentBranch: String = ""
    @State var headHash: String = ""
    @State var branchSyncStatus: [String: BranchSyncStatus] = [:]
    @State var currentBranchIntegrationStatus: CurrentBranchIntegrationStatus?
    @State var activeBranchSyncLoadID: UUID?
    @State var loadedBranchSyncBranches: Set<String> = []
    @State var syncingBranchSyncBranches: Set<String> = []
    @State var expandedFolders: Set<String> = []
    @State var hasLoadedBranches = false
    @State var isLoadingBranches = false
    @State var tagNodes: [BranchNode] = []
    @State var cachedVisibleTagRows: [BranchRowItem] = []
    @State var activeTagLoadID: UUID?
    @State var hasLoadedTags = false
    @State var isLoadingTags = false
    @State var expandedTagFolders: Set<String> = []
    @State var remoteNodes: [BranchNode] = []
    @State var cachedVisibleRemoteRows: [BranchRowItem] = []
    @State var activeRemoteLoadID: UUID?
    @State var hasLoadedRemotes = false
    @State var remoteNames: [String] = []
    @State var branchesByRemote: [String: [String]] = [:]
    @State var upstreamByBranch: [String: String] = [:]
    @State var isLoadingRemotes = false
    @State var expandedRemoteFolders: Set<String> = []
    @State var stashEntries: [StashEntry] = []
    @State var activeStashLoadID: UUID?
    @State var hasLoadedStashes = false
    @State var isLoadingStashes = false
    @State var submoduleEntries: [GitSubmoduleEntry] = []
    @State var cachedVisibleSubmoduleRows: [BranchRowItem] = []
    @State var cachedSubmoduleEntriesByPath: [String: GitSubmoduleEntry] = [:]
    @State var hasLoadedSubmodules = false
    @State var isLoadingSubmodules = false
    @State var expandedSubmoduleFolders: Set<String> = []
    @State var activeSubmoduleLoadID: UUID?
    @State private var submoduleToEdit: GitSubmoduleEntry?
    @State var submoduleToDeinitialize: GitSubmoduleEntry?
    @State var submoduleToRemove: GitSubmoduleEntry?
    @State var forceRemoveSubmodule = false
    @State var subtreeEntries: [GitSubtreeEntry] = []
    @State var hasLoadedSubtrees = false
    @State var isLoadingSubtrees = false
    @State private var subtreeToEdit: GitSubtreeEntry?
    @State var subtreeToUnlink: GitSubtreeEntry?
    @State var worktreeEntries: [WorktreeEntry] = []
    @State var hasLoadedWorktrees = false
    @State var isLoadingWorktrees = false
    @State var activeWorktreeLoadID: UUID?
    @State var activeSubtreeLoadID: UUID?
    @State var worktreeToLabel: WorktreeEntry?
    @State var worktreeLabelInput = ""
    @State var worktreeToLock: WorktreeEntry?
    @State var worktreeLockReasonInput = ""
    @State var isUpdatingWorktreeLock = false
    @State var worktreeToMove: WorktreeEntry?
    @State var worktreeMovePathInput = ""
    @State var worktreeMoveErrorMessage: String?
    @State var isMovingWorktree = false
    @State var worktreeToCheckout: WorktreeEntry?
    @State var availableWorktreeCheckoutBranches: [String] = []
    @State var selectedWorktreeCheckoutBranch = ""
    @State var worktreeCheckoutErrorMessage: String?
    @State var isCheckingOutWorktreeBranch = false
    @State var pendingWorktreeForceCheckout: WorktreeEntry?
    @State var showingWorktreeForceCheckoutConfirmation = false
    @State var missingWorktreeEntry: WorktreeEntry?
    @State var showingMissingWorktreeAlert = false
    @State var pendingWorktreeRemoval: WorktreeEntry?
    @State var showingWorktreeRemovalConfirmation = false
    @State private var showingPruneWorktreesConfirmation = false
    @State var createWorktreeMode: WorktreeCreationMode = .existingBranch
    @State var availableWorktreeBranches: [String] = []
    @State var currentWorktreeBranch = ""
    @State var selectedExistingWorktreeBranch = ""
    @State var newWorktreeBranchName = ""
    @State var newWorktreeBaseBranch = ""
    @State var worktreePathInput = ""
    @State var customWorktreePath = false
    @State var worktreeLabelDraft = ""
    @State var openWorktreeAfterCreate = true
    @State var showingCreateWorktreeSheet = false
    @State var isCreatingWorktree = false
    @State var worktreeCreationErrorMessage: String?
    @State var worktreeRootURL: URL?

    @State var sectionStates = SidebarSectionState()

    @State var errorMessage = ""
    @State var showingError = false
    @State var deleteConfirmationTarget: DeleteConfirmationTarget?
    @State var remoteBranchDeleteTarget: RemoteBranchDeleteTarget?
    @State var forceDeleteBranch = false
    @State var activeDropTarget: GitDragTarget?
    @State var activeDropLabel: String?
    @State var isCurrentBranchDropTargeted = false
    @State var activeBranchDragPayload: GitDragPayload?

    init(
        repositoryURL: URL,
        selection: Binding<SidebarSelection?>,
        undoManager: GitUndoManager? = nil,
        currentBranchFallbackSyncStatus: BranchSyncStatus? = nil,
        defaultRemoteName: String? = nil,
        isAccountMenuDisabled: Bool = false,
        gitFlowConfiguration: GitFlowConfiguration = GitFlowConfiguration(),
        gitFlowFinishCheckpoint: GitFlowFinishCheckpoint? = nil,
        gitFlowRecoveryIssue: GitFlowLocalStateIssue? = nil,
        isGitFlowOperationDisabled: Bool = false,
        isBranchSyncing: @escaping (String) -> Bool = { _ in false },
        activeSyncBranchName: String? = nil,
        canUpdateCurrentBranch: Bool = true,
        onRequestCheckout: @escaping (String, Bool) -> Void,
        onRequestRemoteBranchCheckout: @escaping (RemoteBranchCheckoutTarget) -> Void,
        onRequestFetchBranch: @escaping (String) -> Void,
        onRequestPullRemoteBranch: @escaping (String, String) -> Void = { _, _ in },
        onRequestPullTracked: @escaping (String) -> Void = { _ in },
        onRequestPushToTracked: @escaping (String) -> Void = { _ in },
        onRequestForcePushToTracked: @escaping (String) -> Void = { _ in },
        onRequestForcePushBranchToRemote: @escaping (String, String) -> Void = { _, _ in },
        onRequestUpdateCurrentBranch: @escaping (CurrentBranchIntegrationStatus) -> Void = { _ in },
        onRequestRenameBranch: @escaping (String) -> Void = { _ in },
        onRequestCreatePullRequest: @escaping (String) -> Void = { _ in },
        onRequestCreateBranchFromBranch: @escaping (String) -> Void = { _ in },
        onRequestCreateTagFromBranch: @escaping (String) -> Void = { _ in },
        onRequestTagDetails: @escaping (String) -> Void = { _ in },
        onRequestDiffTagAgainstCurrent: @escaping (String) -> Void = { _ in },
        onRequestCompareBranches: @escaping (String, String) -> Void = { _, _ in },
        onRequestPushTagToRemote: @escaping (String, String) -> Void = { _, _ in },
        onRequestForcePushTagToRemote: @escaping (String, String) -> Void = { _, _ in },
        onRequestDeleteTag: @escaping (String) -> Void = { _ in },
        onRequestRebaseOnto: @escaping (String) -> Void = { _ in },
        onRequestMergeBranchIntoCurrent: @escaping (String) -> Void = { _ in },
        onRequestPushBranchToRemote: @escaping (String, String) -> Void = { _, _ in },
        onRequestTrackRemoteBranch: @escaping (String, String?) -> Void = { _, _ in },
        onRequestCreatePullRequestForRemote: @escaping (String, String) -> Void = { _, _ in },
        onRequestApplyStash: @escaping (String) -> Void = { _ in },
        onRequestDeleteStash: @escaping (String) -> Void = { _ in },
        onRequestOpenWorktree: @escaping (URL) -> Void = { _ in },
        onRequestOpenWorktreeInTerminal: @escaping (URL) -> Void = { _ in },
        onRequestOpenSubmodule: @escaping (URL) -> Void = { _ in },
        onRequestShowSubmoduleInFinder: @escaping (URL) -> Void = { _ in },
        onRequestOpenSubmoduleInTerminal: @escaping (URL) -> Void = { _ in },
        onRequestAddSubmodule: @escaping () -> Void = {},
        onRequestAddLinkSubtree: @escaping () -> Void = {},
        onRequestCreateBranch: @escaping () -> Void = {},
        onRequestCreateTag: @escaping () -> Void = {},
        onRequestCreatePullRequestFromWorkspace: @escaping () -> Void = {},
        onRequestShowSubtreeInFinder: @escaping (URL) -> Void = { _ in },
        onRequestOpenSubtreeInTerminal: @escaping (URL) -> Void = { _ in },
        onRequestPullSubtree: @escaping (GitSubtreeEntry) -> Void = { _ in },
        onRequestPushSubtree: @escaping (GitSubtreeEntry) -> Void = { _ in },
        onRequestUpdateSubtreeLink: @escaping @MainActor (GitSubtreeEntry) async throws -> Void = { _ in },
        onRequestUnlinkSubtree: @escaping @MainActor (GitSubtreeEntry) async throws -> Void = { _ in },
        onRequestInitializeSubmodule: @escaping (String) -> Void = { _ in },
        onRequestUpdateSubmodule: @escaping (String, SubmoduleUpdateMode) -> Void = { _, _ in },
        onRequestSynchronizeSubmoduleURL: @escaping (String) -> Void = { _ in },
        onRequestUpdateSubmoduleSettings: @escaping @MainActor (String, String, String?) async throws -> Void = { _, _, _ in },
        onRequestDeinitializeSubmodule: @escaping @MainActor (String, Bool) async throws -> Void = { _, _ in },
        onRequestRemoveSubmodule: @escaping @MainActor (String, Bool) async throws -> Void = { _, _ in },
        onRequestSearch: @escaping () -> Void = {},
        onRequestStartGitFlow: @escaping (GitFlowTopicKind) -> Void = { _ in },
        onRequestFinishGitFlow: @escaping (GitFlowTopicKind) -> Void = { _ in },
        onRequestResumeGitFlowFinish: @escaping () -> Void = {},
        onRequestAbortGitFlowFinish: @escaping () -> Void = {},
        onRequestEditGitFlow: @escaping () -> Void = {},
        onRequestDisableGitFlow: @escaping () -> Void = {},
        onRequestDragDrop: @escaping (GitDragDropRequest) -> Void = { _ in },
        onRunRepositoryOperation: @escaping RepositoryOperationRunner = { _, operation in
            Task { await operation() }
        }
    ) {
        self.repositoryURL = repositoryURL
        self._selection = selection
        self.undoManager = undoManager
        self.currentBranchFallbackSyncStatus = currentBranchFallbackSyncStatus
        self.defaultRemoteName = defaultRemoteName
        self.isAccountMenuDisabled = isAccountMenuDisabled
        self.gitFlowConfiguration = gitFlowConfiguration
        self.gitFlowFinishCheckpoint = gitFlowFinishCheckpoint
        self.gitFlowRecoveryIssue = gitFlowRecoveryIssue
        self.isGitFlowOperationDisabled = isGitFlowOperationDisabled
        self.isBranchSyncing = isBranchSyncing
        self.activeSyncBranchName = activeSyncBranchName
        self.canUpdateCurrentBranch = canUpdateCurrentBranch
        self.onRequestCheckout = onRequestCheckout
        self.onRequestRemoteBranchCheckout = onRequestRemoteBranchCheckout
        self.onRequestFetchBranch = onRequestFetchBranch
        self.onRequestPullRemoteBranch = onRequestPullRemoteBranch
        self.onRequestPullTracked = onRequestPullTracked
        self.onRequestPushToTracked = onRequestPushToTracked
        self.onRequestForcePushToTracked = onRequestForcePushToTracked
        self.onRequestForcePushBranchToRemote = onRequestForcePushBranchToRemote
        self.onRequestUpdateCurrentBranch = onRequestUpdateCurrentBranch
        self.onRequestRenameBranch = onRequestRenameBranch
        self.onRequestCreatePullRequest = onRequestCreatePullRequest
        self.onRequestCreateBranchFromBranch = onRequestCreateBranchFromBranch
        self.onRequestCreateTagFromBranch = onRequestCreateTagFromBranch
        self.onRequestTagDetails = onRequestTagDetails
        self.onRequestDiffTagAgainstCurrent = onRequestDiffTagAgainstCurrent
        self.onRequestCompareBranches = onRequestCompareBranches
        self.onRequestPushTagToRemote = onRequestPushTagToRemote
        self.onRequestForcePushTagToRemote = onRequestForcePushTagToRemote
        self.onRequestDeleteTag = onRequestDeleteTag
        self.onRequestRebaseOnto = onRequestRebaseOnto
        self.onRequestMergeBranchIntoCurrent = onRequestMergeBranchIntoCurrent
        self.onRequestPushBranchToRemote = onRequestPushBranchToRemote
        self.onRequestTrackRemoteBranch = onRequestTrackRemoteBranch
        self.onRequestCreatePullRequestForRemote = onRequestCreatePullRequestForRemote
        self.onRequestApplyStash = onRequestApplyStash
        self.onRequestDeleteStash = onRequestDeleteStash
        self.onRequestOpenWorktree = onRequestOpenWorktree
        self.onRequestOpenWorktreeInTerminal = onRequestOpenWorktreeInTerminal
        self.onRequestOpenSubmodule = onRequestOpenSubmodule
        self.onRequestShowSubmoduleInFinder = onRequestShowSubmoduleInFinder
        self.onRequestOpenSubmoduleInTerminal = onRequestOpenSubmoduleInTerminal
        self.onRequestAddSubmodule = onRequestAddSubmodule
        self.onRequestAddLinkSubtree = onRequestAddLinkSubtree
        self.onRequestCreateBranch = onRequestCreateBranch
        self.onRequestCreateTag = onRequestCreateTag
        self.onRequestCreatePullRequestFromWorkspace = onRequestCreatePullRequestFromWorkspace
        self.onRequestShowSubtreeInFinder = onRequestShowSubtreeInFinder
        self.onRequestOpenSubtreeInTerminal = onRequestOpenSubtreeInTerminal
        self.onRequestPullSubtree = onRequestPullSubtree
        self.onRequestPushSubtree = onRequestPushSubtree
        self.onRequestUpdateSubtreeLink = onRequestUpdateSubtreeLink
        self.onRequestUnlinkSubtree = onRequestUnlinkSubtree
        self.onRequestInitializeSubmodule = onRequestInitializeSubmodule
        self.onRequestUpdateSubmodule = onRequestUpdateSubmodule
        self.onRequestSynchronizeSubmoduleURL = onRequestSynchronizeSubmoduleURL
        self.onRequestUpdateSubmoduleSettings = onRequestUpdateSubmoduleSettings
        self.onRequestDeinitializeSubmodule = onRequestDeinitializeSubmodule
        self.onRequestRemoveSubmodule = onRequestRemoveSubmodule
        self.onRequestSearch = onRequestSearch
        self.onRequestStartGitFlow = onRequestStartGitFlow
        self.onRequestFinishGitFlow = onRequestFinishGitFlow
        self.onRequestResumeGitFlowFinish = onRequestResumeGitFlowFinish
        self.onRequestAbortGitFlowFinish = onRequestAbortGitFlowFinish
        self.onRequestEditGitFlow = onRequestEditGitFlow
        self.onRequestDisableGitFlow = onRequestDisableGitFlow
        self.onRequestDragDrop = onRequestDragDrop
        self.onRunRepositoryOperation = onRunRepositoryOperation
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarContent

            Divider()
            HStack {
                AccountToolbarMenu(controller: accountController)
                    .labelStyle(.iconOnly)
                    .menuStyle(.borderlessButton)
                    .disabled(isAccountMenuDisabled)

                Menu {
                    sidebarCreationMenu
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .help("Create or add to repository")

                Spacer()

                if let model = UpdateBannerView.Model.make(for: appUpdateController.displayState) {
                    UpdateBannerView(model: model) {
                        appUpdateController.openUpdateWindow()
                    }
                }
            }
            .padding(8)
        }
    }

    var branchSectionActions: SidebarBranchSectionActions {
        SidebarBranchSectionActions(
            toggleSection: { toggleSection(.branches) },
            toggleFolder: toggleFolder,
            select: selectBranch,
            checkout: { onRequestCheckout($0, false) },
            fetch: onRequestFetchBranch,
            pullTracked: onRequestPullTracked,
            pushTracked: onRequestPushToTracked,
            updateCurrentBranch: onRequestUpdateCurrentBranch,
            rename: onRequestRenameBranch,
            createPullRequest: onRequestCreatePullRequest,
            createBranchFrom: onRequestCreateBranchFromBranch,
            createTagFrom: onRequestCreateTagFromBranch,
            rebaseOnto: onRequestRebaseOnto,
            mergeIntoCurrent: onRequestMergeBranchIntoCurrent,
            pushToRemote: onRequestPushBranchToRemote,
            trackRemoteBranch: onRequestTrackRemoteBranch,
            confirmDelete: { deleteConfirmationTarget = $0 },
            makeItemProvider: makeBranchItemProvider,
            setHeaderDropTargeted: updateBranchesHeaderDropTarget,
            setCurrentDropTargeted: updateCurrentBranchDropTarget,
            currentDropLabel: currentBranchDropLabel,
            drop: dropActions,
            forcePushTracked: onRequestForcePushToTracked,
            forcePushToRemote: onRequestForcePushBranchToRemote,
            compare: { onRequestCompareBranches("refs/heads/\($0)", currentBranch) }
        )
    }

    var gitFlowCommandState: GitFlowCommandState {
        GitFlowCommandState(
            isEnabled: gitFlowConfiguration.isEnabled,
            currentKind: GitFlowPlanner().topicKind(for: currentBranch, configuration: gitFlowConfiguration),
            operationInProgress: isGitFlowOperationDisabled,
            hasPendingFinish: gitFlowFinishCheckpoint != nil,
            hasInvalidRecoveryState: gitFlowRecoveryIssue != nil
        )
    }

    func performGitFlowAction(_ action: GitFlowMenuAction) {
        switch action {
        case .start(let kind):
            onRequestStartGitFlow(kind)
        case .finish(let kind):
            onRequestFinishGitFlow(kind)
        case .resumeFinish:
            onRequestResumeGitFlowFinish()
        case .abortFinish:
            onRequestAbortGitFlowFinish()
        case .configure:
            onRequestEditGitFlow()
        case .disable:
            onRequestDisableGitFlow()
        }
    }

    var tagSectionActions: SidebarTagSectionActions {
        SidebarTagSectionActions(
            toggleSection: { toggleSection(.tags) },
            toggleFolder: toggleTagFolder,
            select: selectHistoryReference,
            checkout: { onRequestCheckout($0, true) },
            showDetails: onRequestTagDetails,
            diffAgainstCurrent: onRequestDiffTagAgainstCurrent,
            pushToRemote: onRequestPushTagToRemote,
            forcePushToRemote: onRequestForcePushTagToRemote,
            delete: onRequestDeleteTag,
            setHeaderDropTargeted: updateTagsHeaderDropTarget,
            setTagDropTargeted: updateTagDropTarget,
            isTagDropTargeted: { activeDropTarget == .tag(name: $0) },
            drop: dropActions
        )
    }

    var remoteSectionActions: SidebarRemoteSectionActions {
        SidebarRemoteSectionActions(
            toggleSection: { toggleSection(.remotes) },
            toggleFolder: toggleRemoteFolder,
            select: selectHistoryReference,
            checkoutFromRow: requestRemoteBranchCheckout,
            checkoutFromContextMenu: requestRemoteBranchCheckout,
            pullIntoCurrent: onRequestPullRemoteBranch,
            confirmDelete: { remoteBranchDeleteTarget = $0 },
            createPullRequest: onRequestCreatePullRequestForRemote,
            makePayload: makeRemoteBranchPayload,
            finishDrag: finishRemoteBranchDrag,
            setHeaderDropTargeted: updateRemotesHeaderDropTarget,
            drop: dropActions,
            compare: { onRequestCompareBranches("refs/remotes/\($0)", currentBranch) }
        )
    }

    private func selectBranch(_ newSelection: SidebarSelection) {
        guard case .branch(let branch) = newSelection else {
            selection = newSelection
            return
        }

        let nextFilter = Self.historyFilter(
            afterSelecting: branch,
            currentBranch: currentBranch,
            currentFilter: appState.historyBranchFilter
        )
        selection = newSelection
        appState.historyBranchFilter = nextFilter
    }

    private func selectHistoryReference(_ newSelection: SidebarSelection) {
        selection = newSelection
        if appState.historyBranchFilter != .all {
            switch newSelection {
            case .tag(let name), .remoteBranch(let name):
                appState.historyBranchFilter = .branch(name)
            default:
                break
            }
        }
    }

    static func historyFilter(
        afterSelecting branch: String,
        currentBranch: String,
        currentFilter: HistoryBranchFilter
    ) -> HistoryBranchFilter {
        guard currentFilter != .all else { return .all }
        return branch == currentBranch ? .current : .all
    }

    var stashSectionActions: SidebarStashSectionActions {
        SidebarStashSectionActions(
            toggleSection: { toggleSection(.stashes) },
            select: { selection = $0 },
            apply: onRequestApplyStash,
            delete: onRequestDeleteStash,
            makeItemProvider: makeStashItemProvider,
            setHeaderDropTargeted: updateStashesHeaderDropTarget,
            drop: dropActions
        )
    }

    var submoduleSectionActions: SidebarSubmoduleSectionActions {
        SidebarSubmoduleSectionActions(
            toggleSection: { toggleSection(.submodules) },
            toggleFolder: toggleSubmoduleFolder,
            select: { selection = $0 },
            open: onRequestOpenSubmodule,
            showInFinder: onRequestShowSubmoduleInFinder,
            openInTerminal: onRequestOpenSubmoduleInTerminal,
            initialize: onRequestInitializeSubmodule,
            update: onRequestUpdateSubmodule,
            synchronizeURL: onRequestSynchronizeSubmoduleURL,
            edit: { submoduleToEdit = $0 },
            deinitialize: presentDeinitializeSubmoduleConfirmation,
            remove: presentRemoveSubmoduleConfirmation
        )
    }

    var subtreeSectionActions: SidebarSubtreeSectionActions {
        SidebarSubtreeSectionActions(
            toggleSection: { toggleSection(.subtrees) },
            showInFinder: onRequestShowSubtreeInFinder,
            openInTerminal: onRequestOpenSubtreeInTerminal,
            pull: onRequestPullSubtree,
            push: onRequestPushSubtree,
            edit: { subtreeToEdit = $0 },
            unlink: { subtreeToUnlink = $0 }
        )
    }

    var worktreeSectionActions: SidebarWorktreeSectionActions {
        SidebarWorktreeSectionActions(
            toggleSection: { toggleSection(.worktrees) },
            prepareCreate: {
                onRunRepositoryOperation("Preparing worktree creation...") {
                    await prepareCreateWorktreeSheet()
                }
            },
            confirmPrune: { showingPruneWorktreesConfirmation = true },
            select: selectWorktree,
            open: openWorktree,
            openInTerminal: onRequestOpenWorktreeInTerminal,
            editLabel: beginEditingWorktreeLabel,
            clearLabel: { entry in
                onRunRepositoryOperation("Clearing worktree label...") {
                    await clearWorktreeLabel(entry)
                }
            },
            editLock: beginLockingWorktree,
            unlock: { entry in
                onRunRepositoryOperation("Unlocking \(entry.displayTitle)...") {
                    await unlockWorktree(entry)
                }
            },
            move: beginMovingWorktree,
            switchBranch: { entry in
                onRunRepositoryOperation("Preparing branch switch...") {
                    await prepareCheckoutWorktreeSheet(for: entry)
                }
            },
            confirmRemoval: { entry in
                pendingWorktreeRemoval = entry
                showingWorktreeRemovalConfirmation = true
            }
        )
    }

    private var sidebarContent: some View {
        sidebarList
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .modifier(
                SidebarBranchPresentationModifier(
                    deleteConfirmationTarget: $deleteConfirmationTarget,
                    forceDeleteBranch: $forceDeleteBranch,
                    remoteBranchDeleteTarget: $remoteBranchDeleteTarget,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    currentBranch: currentBranch,
                    branchesUnderPrefix: branchesUnderPrefix,
                    cancelDeleteConfirmation: cancelDeleteConfirmation,
                    confirmDeleteBranch: confirmDeleteBranch,
                    onPrefixDeleteCompleted: refreshAfterBranchDeletion,
                    deleteRemoteBranch: deleteRemoteBranch,
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            )
            .modifier(
                SidebarWorktreePresentationModifier(
                    worktreeToLabel: $worktreeToLabel,
                    worktreeLabelInput: $worktreeLabelInput,
                    worktreeToLock: $worktreeToLock,
                    worktreeLockReasonInput: $worktreeLockReasonInput,
                    isUpdatingWorktreeLock: isUpdatingWorktreeLock,
                    worktreeToMove: $worktreeToMove,
                    worktreeMovePathInput: $worktreeMovePathInput,
                    worktreeMoveErrorMessage: $worktreeMoveErrorMessage,
                    canMoveWorktree: canMoveWorktree,
                    isMovingWorktree: isMovingWorktree,
                    worktreeToCheckout: $worktreeToCheckout,
                    availableWorktreeCheckoutBranches: $availableWorktreeCheckoutBranches,
                    selectedWorktreeCheckoutBranch: $selectedWorktreeCheckoutBranch,
                    worktreeCheckoutErrorMessage: $worktreeCheckoutErrorMessage,
                    canCheckoutWorktreeBranch: canCheckoutWorktreeBranch,
                    isCheckingOutWorktreeBranch: isCheckingOutWorktreeBranch,
                    showingCreateWorktreeSheet: $showingCreateWorktreeSheet,
                    createWorktreeMode: $createWorktreeMode,
                    availableWorktreeBranches: availableWorktreeBranches,
                    selectedExistingWorktreeBranch: $selectedExistingWorktreeBranch,
                    newWorktreeBranchName: $newWorktreeBranchName,
                    newWorktreeBaseBranch: $newWorktreeBaseBranch,
                    worktreePathInput: $worktreePathInput,
                    worktreeLabelDraft: $worktreeLabelDraft,
                    openWorktreeAfterCreate: $openWorktreeAfterCreate,
                    worktreeCreationErrorMessage: worktreeCreationErrorMessage,
                    canCreateWorktree: canCreateWorktree,
                    isCreatingWorktree: isCreatingWorktree,
                    showingWorktreeRemovalConfirmation: $showingWorktreeRemovalConfirmation,
                    showingMissingWorktreeAlert: $showingMissingWorktreeAlert,
                    showingWorktreeForceCheckoutConfirmation: $showingWorktreeForceCheckoutConfirmation,
                    showingPruneWorktreesConfirmation: $showingPruneWorktreesConfirmation,
                    pendingWorktreeRemoval: $pendingWorktreeRemoval,
                    pendingWorktreeForceCheckout: $pendingWorktreeForceCheckout,
                    missingWorktreeEntry: $missingWorktreeEntry,
                    worktreeRemovalNeedsForce: worktreeRemovalNeedsForce,
                    worktreeRemovalMessage: worktreeRemovalMessage,
                    saveWorktreeLabel: saveWorktreeLabel,
                    lockWorktree: lockWorktree,
                    moveWorktree: moveWorktree,
                    checkoutWorktree: checkoutWorktree,
                    onCreateWorktreeModeChange: { refreshWorktreePathIfNeeded(force: false) },
                    onSelectedExistingWorktreeBranchChange: { refreshWorktreePathIfNeeded(force: false) },
                    onNewWorktreeBranchNameChange: { refreshWorktreePathIfNeeded(force: false) },
                    onWorktreePathChange: { newValue in
                        customWorktreePath = newValue != defaultWorktreePath().path
                    },
                    createWorktree: createWorktree,
                    chooseReplacementWorktreeFolder: chooseReplacementWorktreeFolder,
                    deleteMissingWorktree: deleteMissingWorktree,
                    removeWorktree: removeWorktree,
                    pruneWorktrees: pruneWorktrees,
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            )
            .modifier(
                SidebarSubtreePresentationModifier(
                    subtreeToEdit: $subtreeToEdit,
                    subtreeToUnlink: $subtreeToUnlink,
                    updateSubtree: { updated in
                        try await onRequestUpdateSubtreeLink(updated)
                    },
                    unlinkSubtree: unlinkSubtree,
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            )
            .modifier(
                SubmoduleLifecyclePresentationModifier(
                    submoduleToEdit: $submoduleToEdit,
                    submoduleToDeinitialize: $submoduleToDeinitialize,
                    submoduleToRemove: $submoduleToRemove,
                    forceRemoveSubmodule: $forceRemoveSubmodule,
                    onSaveSettings: { entry, url, branch in
                        try await onRequestUpdateSubmoduleSettings(entry.path, url, branch)
                    },
                    onDeinitialize: runSubmoduleDeinitialize,
                    onRemove: runSubmoduleRemove,
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            )
    }

    private var sidebarList: some View {
        SidebarNativeList(repositoryURL: repositoryURL, input: nativeInput,
            makeRows: { sidebarDataRepositoryURL == repositoryURL ? nativeRows : [] }, selection: selection,
            textScale: textScale, backgroundMenu: nativeBackgroundMenu,
            acceptDrop: { payload, target, option in
                guard canAcceptDrop(payload, target: target, optionKeyPressed: option) else { return false }
                handleDrop([payload], target: target, optionKeyPressed: option)
                return true
            })
        .task(id: "\(repositoryURL.path)|\(appState.showSubmodules)") {
            loadSectionStates()
            resetLazySectionData()
            await loadAllSections(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                let checkedOutBranch = notification.userInfo?["checkedOutBranch"] as? String
                if checkedOutBranch != nil {
                    expandBranchesSection()
                }
                Task {
                    await loadAllSections(force: true)
                    if let checkedOutBranch {
                        expandedFolders.formUnion(
                            SidebarTreeBuilder.expandedFolderPaths(revealing: checkedOutBranch)
                        )
                        cachedVisibleBranchRows = SidebarTreeBuilder.visibleRows(from: branchNodes, expandedFolders: expandedFolders)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await loadLocalRefreshSections()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryRemoteRefsDidRefresh)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await loadBranches(force: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryCurrentBranchDidChange)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await GitStatusService.shared.invalidateBranchListCache(in: repositoryURL)
                    await loadBranches(force: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryBranchDidCreate)) { notification in
            guard let url = notification.userInfo?["repositoryURL"] as? URL,
                  let branchName = notification.userInfo?["branchName"] as? String,
                  url == repositoryURL else {
                return
            }

            expandedFolders.formUnion(
                SidebarTreeBuilder.expandedFolderPaths(revealing: branchName)
            )
            Task {
                await loadBranches(force: true)
            }
        }
        .onChange(of: appState.showSubtrees) { _, isVisible in
            guard isVisible, sectionStates.subtreesExpanded else { return }
            Task {
                await loadSubtrees(force: false)
            }
        }
    }

    @ViewBuilder
    private var sidebarCreationMenu: some View {
        Button("Add Submodule...", systemImage: "plus", action: onRequestAddSubmodule)
        Button("Add/Link Subtree...", systemImage: "plus", action: onRequestAddLinkSubtree)
        Divider()
        Button("New Branch...", systemImage: "arrow.triangle.branch", action: onRequestCreateBranch)
        Button("New Tag...", systemImage: "tag", action: onRequestCreateTag)
    }

}

#Preview {
    SidebarView(
        repositoryURL: URL(fileURLWithPath: "/tmp"),
        selection: .constant(nil),
        isBranchSyncing: { _ in false },
        onRequestCheckout: { _, _ in },
        onRequestRemoteBranchCheckout: { _ in },
        onRequestFetchBranch: { _ in },
        onRequestPullTracked: { _ in },
        onRequestPushToTracked: { _ in },
        onRequestRenameBranch: { _ in },
        onRequestCreatePullRequest: { _ in },
        onRequestRebaseOnto: { _ in },
        onRequestMergeBranchIntoCurrent: { _ in },
        onRequestOpenWorktree: { _ in },
        onRequestOpenWorktreeInTerminal: { _ in }
    )
    .environmentObject(AppState.shared)
}
