//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import SwiftUI

extension SidebarView {
    func resetLazySectionData() {
        sidebarDataRepositoryURL = repositoryURL
        activeBranchSyncLoadID = nil
        activeSubmoduleLoadID = nil
        activeWorktreeLoadID = nil
        activeSubtreeLoadID = nil
        branchNodes = []
        cachedVisibleBranchRows = []
        currentBranch = ""
        headHash = ""
        branchSyncStatus = [:]
        currentBranchIntegrationStatus = nil
        loadedBranchSyncBranches = []
        syncingBranchSyncBranches = []
        expandedFolders = []
        hasLoadedBranches = false
        isLoadingBranches = false

        hasLoadedTags = false
        tagNodes = []
        cachedVisibleTagRows = []
        isLoadingTags = false
        activeTagLoadID = nil

        hasLoadedRemotes = false
        remoteNodes = []
        remoteNames = []
        branchesByRemote = [:]
        upstreamByBranch = [:]
        cachedVisibleRemoteRows = []
        isLoadingRemotes = false
        activeRemoteLoadID = nil

        hasLoadedStashes = false
        stashEntries = []
        isLoadingStashes = false
        activeStashLoadID = nil

        worktreeEntries = []
        hasLoadedWorktrees = false
        isLoadingWorktrees = false

        submoduleEntries = []
        cachedVisibleSubmoduleRows = []
        cachedSubmoduleEntriesByPath = [:]
        hasLoadedSubmodules = false
        isLoadingSubmodules = false

        subtreeEntries = []
        hasLoadedSubtrees = false
        isLoadingSubtrees = false
    }

    func loadVisibleSections(force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            if sectionStates.branchesExpanded {
                group.addTask {
                    await loadBranches(force: force)
                }
            }
            if sectionStates.worktreesExpanded {
                group.addTask {
                    await loadWorktrees(force: force)
                }
            }
            if appState.showSubmodules && sectionStates.submodulesExpanded {
                group.addTask {
                    await loadSubmodules(force: force)
                }
            }
            if appState.showSubtrees && sectionStates.subtreesExpanded {
                group.addTask {
                    await loadSubtrees(force: force)
                }
            }
        }
    }

    func loadAllSections(force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await loadVisibleSections(force: force)
            }
            group.addTask {
                await loadTags()
            }
            group.addTask {
                await loadRemotes()
            }
            group.addTask {
                await loadStashes()
            }
        }
    }

    func loadLocalRefreshSections() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await loadTags()
            }
            group.addTask {
                await loadStashes()
            }
            group.addTask {
                await loadWorktrees(force: true)
            }
        }
    }

    func loadSectionIfNeeded(_ section: SidebarSection) async {
        switch section {
        case .branches:
            if sectionStates.branchesExpanded {
                await loadBranches(force: false)
            }
        case .worktrees:
            if sectionStates.worktreesExpanded {
                await loadWorktrees(force: false)
            }
        case .submodules:
            if appState.showSubmodules && sectionStates.submodulesExpanded {
                await loadSubmodules(force: false)
            }
        case .subtrees:
            if appState.showSubtrees && sectionStates.subtreesExpanded {
                await loadSubtrees(force: false)
            }
        default:
            break
        }
    }

    var visibleBranchRows: [BranchRowItem] {
        cachedVisibleBranchRows
    }

    var visibleTagRows: [BranchRowItem] {
        cachedVisibleTagRows
    }

    var visibleSubmoduleRows: [BranchRowItem] {
        cachedVisibleSubmoduleRows
    }

    var submoduleEntriesByPath: [String: GitSubmoduleEntry] {
        cachedSubmoduleEntriesByPath
    }

    var visibleRemoteRows: [BranchRowItem] {
        cachedVisibleRemoteRows
    }

    func loadBranches(force: Bool = false) async {
        if !force && hasLoadedBranches {
            return
        }

        let loadID = UUID()
        activeBranchSyncLoadID = loadID
        isLoadingBranches = !hasLoadedBranches

        let (locals, current) = await (
            GitStatusService.shared.cachedLocalBranches(in: repositoryURL),
            GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        )
        guard activeBranchSyncLoadID == loadID else { return }
        let filteredLocals = locals.filter { $0 != "HEAD" && !$0.contains("HEAD detached") }
        let tree = SidebarTreeBuilder.buildTree(from: filteredLocals)
        let allFolders = collectFolderPaths(from: tree)
        let hadLoadedBranches = hasLoadedBranches
        let currentBranchFolders = SidebarTreeBuilder.expandedFolderPaths(revealing: current)
            .intersection(allFolders)
        let expandedFoldersForLoad = hadLoadedBranches
            ? expandedFolders.intersection(allFolders)
            : currentBranchFolders

        await MainActor.run {
            guard activeBranchSyncLoadID == loadID else { return }
            branchNodes = tree
            currentBranch = current
            headHash = ""
            let existingBranches = Set(filteredLocals)
            branchSyncStatus = branchSyncStatus.filter { existingBranches.contains($0.key) }
            if currentBranchIntegrationStatus?.branch != current {
                currentBranchIntegrationStatus = nil
            }
            loadedBranchSyncBranches = []
            syncingBranchSyncBranches = []
            // Reveal the current branch only on the initial load. Refreshes
            // preserve the user's tree state while dropping removed folders.
            expandedFolders = expandedFoldersForLoad
            cachedVisibleBranchRows = SidebarTreeBuilder.visibleRows(
                from: tree,
                expandedFolders: expandedFoldersForLoad
            )
            hasLoadedBranches = true
            isLoadingBranches = false
        }

        if current.isEmpty {
            Task {
                guard let hash = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL) else { return }
                await MainActor.run {
                    guard activeBranchSyncLoadID == loadID else { return }
                    headHash = String(hash.prefix(7))
                }
            }
        }

        let initiallyVisibleBranches = cachedVisibleBranchRows
        .filter { !$0.isFolder }
        .map(\.fullPath)
        startBranchSync(for: initiallyVisibleBranches, loadID: loadID)
        if !current.isEmpty {
            let integrationStatus = await GitStatusService.shared.currentBranchIntegrationStatus(
                branch: current,
                preferredRemote: defaultRemoteName,
                gitFlowConfiguration: gitFlowConfiguration,
                in: repositoryURL
            )
            await MainActor.run {
                guard activeBranchSyncLoadID == loadID else { return }
                currentBranchIntegrationStatus = integrationStatus
            }
        }
    }

    func startBranchSync(for branches: [String], loadID: UUID) {
        let pendingBranches = branches.filter {
            $0 != currentBranch
                && !loadedBranchSyncBranches.contains($0)
                && !syncingBranchSyncBranches.contains($0)
        }
        guard !pendingBranches.isEmpty else { return }

        syncingBranchSyncBranches.formUnion(pendingBranches)
        Task {
            await loadBranchSyncStatuses(for: pendingBranches, loadID: loadID)
        }
    }

    private func loadBranchSyncStatuses(for branches: [String], loadID: UUID) async {
        let statuses = await GitStatusService.shared.branchSyncStatuses(
            for: branches,
            in: repositoryURL
        )

        await MainActor.run {
            guard activeBranchSyncLoadID == loadID else { return }
            var updatedStatuses = branchSyncStatus
            for branch in branches {
                if let status = statuses[branch] {
                    updatedStatuses[branch] = status
                } else {
                    updatedStatuses.removeValue(forKey: branch)
                }
            }
            branchSyncStatus = updatedStatuses
            loadedBranchSyncBranches.formUnion(branches)
            syncingBranchSyncBranches.subtract(branches)
        }
    }

    func loadTags() async {
        let loadID = UUID()
        activeTagLoadID = loadID
        isLoadingTags = !hasLoadedTags

        let tags = await GitStatusService.shared.tags(in: repositoryURL)
        guard activeTagLoadID == loadID else { return }
        let tree = SidebarTreeBuilder.buildTree(from: tags)
        let allFolders = collectFolderPaths(from: tree)

        await MainActor.run {
            tagNodes = tree
            cachedVisibleTagRows = SidebarTreeBuilder.visibleRows(
                from: tree,
                expandedFolders: expandedTagFolders.isEmpty ? allFolders : expandedTagFolders
            )
            hasLoadedTags = true
            isLoadingTags = false
            activeTagLoadID = nil
            if expandedTagFolders.isEmpty {
                expandedTagFolders = allFolders
            }
        }
    }

    func loadRemotes() async {
        let loadID = UUID()
        activeRemoteLoadID = loadID
        isLoadingRemotes = !hasLoadedRemotes

        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        let fetchedBranchesByRemote = await withTaskGroup(
            of: (String, [String]).self,
            returning: [String: [String]].self
        ) { group in
            for remote in remotes {
                group.addTask {
                    let branches = await GitStatusService.shared.cachedRemoteBranches(
                        remote: remote,
                        in: repositoryURL
                    )
                    return (remote, branches)
                }
            }

            var result: [String: [String]] = [:]
            for await (remote, branches) in group {
                result[remote] = branches
            }
            return result
        }
        let upstreams = await GitStatusService.shared.localBranchUpstreams(in: repositoryURL)
        guard activeRemoteLoadID == loadID else { return }

        let tree = SidebarTreeBuilder.buildRemoteTree(remoteBranchesByRemote: fetchedBranchesByRemote)
        await MainActor.run {
            remoteNodes = tree
            cachedVisibleRemoteRows = SidebarTreeBuilder.visibleRows(
                from: tree,
                expandedFolders: expandedRemoteFolders
            )
            remoteNames = remotes
            branchesByRemote = fetchedBranchesByRemote
            upstreamByBranch = upstreams
            hasLoadedRemotes = true
            isLoadingRemotes = false
            activeRemoteLoadID = nil
            if expandedRemoteFolders.isEmpty {
                expandedRemoteFolders = []
            }
        }
    }

    func loadStashes() async {
        let loadID = UUID()
        activeStashLoadID = loadID
        isLoadingStashes = !hasLoadedStashes

        let stashes = await GitStatusService.shared.stashes(in: repositoryURL)
        guard activeStashLoadID == loadID else { return }
        await MainActor.run {
            if case .stash(let ref) = selection,
               let previous = stashEntries.first(where: { $0.ref == ref }), let objectID = previous.objectID {
                let matches = stashes.filter { $0.objectID == objectID }
                // Ambiguous duplicate stash objects must not silently select another entry.
                selection = matches.count == 1 ? .stash(matches[0].ref) : nil
            }
            stashEntries = stashes
            hasLoadedStashes = true
            isLoadingStashes = false
            activeStashLoadID = nil
        }
    }

    func collectFolderPaths(from nodes: [BranchNode]) -> Set<String> {
        var paths = Set<String>()
        for node in nodes where node.isFolder {
            paths.insert(node.fullPath)
            paths.formUnion(collectFolderPaths(from: node.children))
        }
        return paths
    }
}
