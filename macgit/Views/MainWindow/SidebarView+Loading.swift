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
        branchNodes = []
        currentBranch = ""
        headHash = ""
        branchSyncStatus = [:]
        currentBranchIntegrationStatus = nil
        loadedBranchSyncBranches = []
        syncingBranchSyncBranches = []
        expandedFolders = []
        hasLoadedBranches = false
        isLoadingBranches = false

        worktreeEntries = []
        hasLoadedWorktrees = false
        isLoadingWorktrees = false

        submoduleEntries = []
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
        SidebarTreeBuilder.visibleRows(from: branchNodes, expandedFolders: expandedFolders)
    }

    var visibleTagRows: [BranchRowItem] {
        SidebarTreeBuilder.visibleRows(from: tagNodes, expandedFolders: expandedTagFolders)
    }

    var visibleSubmoduleRows: [BranchRowItem] {
        SidebarTreeBuilder.visibleRows(
            from: SidebarTreeBuilder.buildTree(from: submoduleEntries.map(\.path)),
            expandedFolders: expandedSubmoduleFolders
        )
    }

    var submoduleEntriesByPath: [String: GitSubmoduleEntry] {
        Dictionary(uniqueKeysWithValues: submoduleEntries.map { ($0.path, $0) })
    }

    var visibleRemoteRows: [BranchRowItem] {
        SidebarTreeBuilder.visibleRows(from: remoteNodes, expandedFolders: expandedRemoteFolders)
    }

    func loadBranches(force: Bool = false) async {
        if !force && hasLoadedBranches {
            return
        }

        isLoadingBranches = true
        defer { isLoadingBranches = false }

        let (locals, current) = await (
            GitStatusService.shared.cachedLocalBranches(in: repositoryURL),
            GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        )
        let filteredLocals = locals.filter { $0 != "HEAD" && !$0.contains("HEAD detached") }
        let tree = SidebarTreeBuilder.buildTree(from: filteredLocals)
        let allFolders = collectFolderPaths(from: tree)
        let loadID = UUID()
        let hadLoadedBranches = hasLoadedBranches
        let currentBranchFolders = SidebarTreeBuilder.expandedFolderPaths(revealing: current)
            .intersection(allFolders)
        let expandedFoldersForLoad = hadLoadedBranches
            ? expandedFolders.intersection(allFolders)
            : currentBranchFolders
        activeBranchSyncLoadID = loadID

        await MainActor.run {
            guard activeBranchSyncLoadID == loadID else { return }
            branchNodes = tree
            currentBranch = current
            headHash = ""
            branchSyncStatus = [:]
            if currentBranchIntegrationStatus?.branch != current {
                currentBranchIntegrationStatus = nil
            }
            loadedBranchSyncBranches = []
            syncingBranchSyncBranches = []
            // Reveal the current branch only on the initial load. Refreshes
            // preserve the user's tree state while dropping removed folders.
            expandedFolders = expandedFoldersForLoad
            hasLoadedBranches = true
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

        let initiallyVisibleBranches = filteredLocals.filter { branch in
            branch == current
                || !branch.contains("/")
                || expandedFoldersForLoad.contains { folder in
                    branch.hasPrefix(folder + "/")
                }
        }
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
            !loadedBranchSyncBranches.contains($0)
                && !syncingBranchSyncBranches.contains($0)
        }
        guard !pendingBranches.isEmpty else { return }

        syncingBranchSyncBranches.formUnion(pendingBranches)
        Task {
            await loadBranchSyncStatuses(for: pendingBranches, loadID: loadID)
        }
    }

    private func loadBranchSyncStatuses(for branches: [String], loadID: UUID) async {
        await withTaskGroup(of: (String, BranchSyncStatus?).self) { group in
            for branch in branches {
                group.addTask {
                    let status = await GitStatusService.shared.branchSyncStatus(
                        for: branch,
                        in: repositoryURL
                    )
                    return (branch, status)
                }
            }

            for await result in group {
                await MainActor.run {
                    guard activeBranchSyncLoadID == loadID else { return }
                    let (branch, status) = result
                    if let status {
                        branchSyncStatus[branch] = status
                    }
                    loadedBranchSyncBranches.insert(branch)
                    syncingBranchSyncBranches.remove(branch)
                }
            }
        }

        await MainActor.run {
            if activeBranchSyncLoadID == loadID {
                for branch in branches {
                    syncingBranchSyncBranches.remove(branch)
                }
            }
        }
    }

    func loadTags() async {
        isLoadingTags = true
        defer { isLoadingTags = false }

        let tags = await GitStatusService.shared.tags(in: repositoryURL)
        let tree = SidebarTreeBuilder.buildTree(from: tags)
        let allFolders = collectFolderPaths(from: tree)

        await MainActor.run {
            tagNodes = tree
            if expandedTagFolders.isEmpty {
                expandedTagFolders = allFolders
            }
        }
    }

    func loadRemotes() async {
        isLoadingRemotes = true
        defer { isLoadingRemotes = false }

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

        let tree = SidebarTreeBuilder.buildRemoteTree(remoteBranchesByRemote: fetchedBranchesByRemote)
        await MainActor.run {
            remoteNodes = tree
            remoteNames = remotes
            branchesByRemote = fetchedBranchesByRemote
            upstreamByBranch = upstreams
            if expandedRemoteFolders.isEmpty {
                expandedRemoteFolders = []
            }
        }
    }

    func loadStashes() async {
        isLoadingStashes = true
        defer { isLoadingStashes = false }

        let stashes = await GitStatusService.shared.stashes(in: repositoryURL)
        await MainActor.run {
            stashEntries = stashes
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
