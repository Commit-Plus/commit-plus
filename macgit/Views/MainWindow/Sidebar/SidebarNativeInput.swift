// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The coordinator compares source values before flattening presentation rows.
/// Selection and pointer/scroll state deliberately do not invalidate this input.
struct SidebarNativeInput: Equatable {
    let trees: [[BranchRowItem]]
    let expanded: [Set<String>]
    let flags: [Bool]
    let currentBranch: String
    let headHash: String
    let sync: [String: BranchSyncStatus]
    let fallbackSync: BranchSyncStatus?
    let integration: CurrentBranchIntegrationStatus?
    let syncingBranches: Set<String>
    let remotes: [String]
    let remoteBranches: [String: [String]]
    let upstream: [String: String]
    let gitFlow: GitFlowConfiguration
    let gitFlowCommands: GitFlowCommandState
    let worktrees: [WorktreeEntry]
    let stashes: [StashEntry]
    let submodules: [GitSubmoduleEntry]
    let subtrees: [GitSubtreeEntry]
    var dataRepositoryURL: URL? = nil
}

extension SidebarView {
    var nativeInput: SidebarNativeInput {
        SidebarNativeInput(
            trees: [visibleBranchRows, visibleTagRows, visibleRemoteRows, visibleSubmoduleRows],
            expanded: [expandedFolders, expandedTagFolders, expandedRemoteFolders, expandedSubmoduleFolders],
            flags: [sectionStates.branchesExpanded, sectionStates.tagsExpanded, sectionStates.remotesExpanded,
                sectionStates.worktreesExpanded, sectionStates.stashesExpanded, sectionStates.submodulesExpanded,
                sectionStates.subtreesExpanded, appState.showTags, appState.showWorktrees, appState.showSubmodules,
                appState.showSubtrees, appState.showGitFlow, appState.showWorkspaceReflog,
                appState.showWorkspacePullRequests, appState.showWorkspaceGitLFS, isLoadingBranches,
                isLoadingTags, isLoadingRemotes, isLoadingWorktrees, isLoadingStashes,
                isLoadingSubmodules, isLoadingSubtrees, canUpdateCurrentBranch],
            currentBranch: currentBranch, headHash: headHash, sync: branchSyncStatus,
            fallbackSync: currentBranchFallbackSyncStatus, integration: currentBranchIntegrationStatus,
            syncingBranches: Set(activeSyncBranchName.map { [$0] } ?? []),
            remotes: remoteNames, remoteBranches: branchesByRemote, upstream: upstreamByBranch,
            gitFlow: gitFlowConfiguration, gitFlowCommands: gitFlowCommandState,
            worktrees: worktreeEntries, stashes: stashEntries, submodules: submoduleEntries, subtrees: subtreeEntries,
            dataRepositoryURL: sidebarDataRepositoryURL)
    }
}
