// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

extension SidebarView {
    var nativeRows: [SidebarNativeRow] {
        var result: [SidebarNativeRow] = []
        func header(_ section: SidebarSection, expanded: Bool, target: GitDragTarget? = nil,
                    accessory: String = "", label: String = "", action: ((NSView) -> Void)? = nil) {
            var row = SidebarNativeRow(id: .init(section: section, kind: "header", key: ""),
                appearance: .init(title: section.rawValue, icon: section.icon,
                    badge: section == .workspace ? "" : expanded ? "⌄" : "›", header: true,
                    accessory: accessory, accessoryLabel: label))
            if section != .workspace { row.select = { toggleSection(section) } }
            row.accessory = action
            row.appearance.tint = section.rawValue
            row.dropTarget = target
            if section == .worktrees {
                row.menu = {
                    let menu = SidebarNativeMenu()
                    menu.item("Create Worktree", worktreeSectionActions.prepareCreate)
                    menu.item(WorktreeHeaderAction.prune.rawValue, worktreeSectionActions.confirmPrune)
                    return menu
                }
            }
            result.append(row)
        }
        func empty(_ section: SidebarSection, loading: Bool) {
            result.append(.init(id: .init(section: section, kind: "status", key: ""),
                appearance: .init(title: loading ? "Loading…" : "No \(section.rawValue.lowercased())", spinning: loading)))
        }
        func folder(_ item: BranchRowItem, section: SidebarSection, expanded: Set<String>, toggle: @escaping (String) -> Void) -> SidebarNativeRow {
            var row = SidebarNativeRow(id: .init(section: section, kind: "folder", key: item.fullPath),
                appearance: .init(title: item.name, icon: expanded.contains(item.fullPath) ? "chevron.down" : "chevron.right", indent: item.indent))
            row.select = { toggle(item.fullPath) }
            if section == .branches {
                row.menu = {
                    let menu = SidebarNativeMenu()
                    menu.item("Delete All in “\(item.fullPath)/”…", enabled: branchesUnderPrefix(item.fullPath).contains { $0 != currentBranch }) {
                        branchSectionActions.confirmDelete(.prefix(item.fullPath))
                    }
                    menu.separator()
                    menu.copy("Copy Folder Name to Clipboard", value: item.fullPath)
                    return menu
                }
            }
            return row
        }
        header(.workspace, expanded: true, accessory: "line.3.horizontal.decrease.circle", label: "Customize Workspace") { view in
            SidebarNativePopover.show(WorkspaceVisibilityPopover(appState: appState), from: view)
        }
        for item in SidebarSection.workspace.items + (appState.showGitFlow ? [.gitFlow] : []) {
            if item == .reflog && !appState.showWorkspaceReflog { continue }
            if item == .pullRequests && !appState.showWorkspacePullRequests { continue }
            if item == .gitLFS && !appState.showWorkspaceGitLFS { continue }
            var row = SidebarNativeRow(id: .init(section: .workspace, kind: "item", key: item.rawValue),
                appearance: .init(title: item.rawValue, icon: item.icon))
            if item == .search { row.select = onRequestSearch }
            else {
                row.selection = .item(item)
                row.select = { if selection != .item(item) { selection = .item(item) } }
            }
            if item == .pullRequests {
                row.menu = { let menu = SidebarNativeMenu(); menu.item("Create Pull Request...", onRequestCreatePullRequestFromWorkspace); return menu }
            } else if item == .gitFlow { row.menu = nativeGitFlowMenu }
            result.append(row)
        }
        header(.branches, expanded: sectionStates.branchesExpanded, target: .branchesHeader)
        if sectionStates.branchesExpanded {
            if currentBranch.isEmpty && !headHash.isEmpty {
                result.append(.init(id: .init(section: .branches, kind: "head", key: headHash),
                    appearance: .init(title: "HEAD \(headHash)", icon: "circle.fill", emphasized: true),
                    selection: .head(headHash), select: { branchSectionActions.select(.head(headHash)) }))
            }
            if visibleBranchRows.isEmpty { empty(.branches, loading: isLoadingBranches) }
            for item in visibleBranchRows {
                if item.isFolder { result.append(folder(item, section: .branches, expanded: expandedFolders, toggle: toggleFolder)); continue }
                let current = item.fullPath == currentBranch
                let sync = SidebarBranchSyncBadgeResolver.status(for: item.fullPath, currentBranch: currentBranch,
                    branchSyncStatus: branchSyncStatus, currentBranchFallbackSyncStatus: currentBranchFallbackSyncStatus)
                var badges: [String] = []
                if let role = GitFlowBranchRoleResolver().role(for: item.fullPath, configuration: gitFlowConfiguration) { badges.append(role.rawValue) }
                if let sync {
                    if sync.ahead > 0 { badges.append("↑\(sync.ahead)") }
                    if sync.behind > 0 { badges.append("↓\(sync.behind)") }
                }
                if current { badges.append("HEAD") }
                var row = SidebarNativeRow(id: .init(section: .branches, kind: "ref", key: item.fullPath),
                    appearance: .init(title: item.name, icon: current ? "circle.fill" : "", badge: badges.joined(separator: "  "), indent: item.indent, emphasized: current),
                    selection: .branch(item.fullPath), select: { branchSectionActions.select(.branch(item.fullPath)) },
                    activate: { if !current { branchSectionActions.checkout(item.fullPath) } },
                    menu: { nativeBranchMenu(item.fullPath) },
                    payload: { GitDragPayload.branch(item.fullPath, repositoryURL: repositoryURL) },
                    dropTarget: .localBranch(name: item.fullPath, isCurrent: current))
                if current, let status = currentBranchIntegrationStatus, status.predictsBaseConflict {
                    row.appearance.accessory = "exclamationmark.triangle.fill"
                    row.appearance.accessoryLabel = "Current branch integration status"
                    row.accessory = { view in
                        SidebarNativePopover.show(CurrentBranchIntegrationWarningDetails(status: status,
                            canUpdate: canUpdateCurrentBranch, onUpdate: { onRequestUpdateCurrentBranch(status) }), from: view)
                    }
                }
                row.appearance.spinning = isBranchSyncing(item.fullPath)
                result.append(row)
            }
        }
        if appState.showWorktrees {
            header(.worktrees, expanded: sectionStates.worktreesExpanded, accessory: "plus", label: "Worktree Actions") { view in
                let menu = SidebarNativeMenu()
                menu.item("Create Worktree", worktreeSectionActions.prepareCreate)
                menu.item(WorktreeHeaderAction.prune.rawValue, worktreeSectionActions.confirmPrune)
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
            }
            if sectionStates.worktreesExpanded {
                if worktreeEntries.isEmpty { empty(.worktrees, loading: isLoadingWorktrees) }
                for entry in worktreeEntries {
                    let current = entry.path.standardizedFileURL == repositoryURL.standardizedFileURL
                    result.append(.init(id: .init(section: .worktrees, kind: "entry", key: entry.path.path),
                        appearance: .init(title: entry.displayTitle + (current ? " (this)" : ""), icon: entry.isLocked ? "lock.fill" : current ? "circle.fill" : "folder",
                            badge: current || entry.dirtyCount == 0 ? "" : entry.dirtyCount < 0 ? "?" : "\(entry.dirtyCount)", emphasized: current, italic: current),
                        selection: .worktree(entry.path), select: { worktreeSectionActions.select(entry) }, activate: { worktreeSectionActions.open(entry) },
                        menu: { nativeWorktreeMenu(entry) }))
                }
            }
        }
        if appState.showTags {
            header(.tags, expanded: sectionStates.tagsExpanded, target: .tagsHeader)
            if sectionStates.tagsExpanded {
                if visibleTagRows.isEmpty { empty(.tags, loading: isLoadingTags) }
                for item in visibleTagRows {
                    if item.isFolder { result.append(folder(item, section: .tags, expanded: expandedTagFolders, toggle: toggleTagFolder)); continue }
                    result.append(.init(id: .init(section: .tags, kind: "ref", key: item.fullPath),
                        appearance: .init(title: item.name, icon: "tag", indent: item.indent), selection: .tag(item.fullPath),
                        select: { tagSectionActions.select(.tag(item.fullPath)) }, activate: { tagSectionActions.checkout(item.fullPath) },
                        menu: { nativeTagMenu(item.fullPath) }, dropTarget: .tag(name: item.fullPath)))
                }
            }
        }
        header(.remotes, expanded: sectionStates.remotesExpanded, target: .remotesHeader)
        if sectionStates.remotesExpanded {
            if visibleRemoteRows.isEmpty { empty(.remotes, loading: isLoadingRemotes) }
            for item in visibleRemoteRows {
                if item.isFolder { result.append(folder(item, section: .remotes, expanded: expandedRemoteFolders, toggle: toggleRemoteFolder)); continue }
                let symbolic = item.fullPath.split(separator: "/", maxSplits: 1).last == "HEAD"
                result.append(.init(id: .init(section: .remotes, kind: "ref", key: item.fullPath),
                    appearance: .init(title: item.name, indent: item.indent), selection: .remoteBranch(item.fullPath),
                    select: { remoteSectionActions.select(.remoteBranch(item.fullPath)) },
                    activate: { if !symbolic { remoteSectionActions.checkoutFromRow(item.fullPath) } },
                    menu: { nativeRemoteMenu(item.fullPath) },
                    payload: symbolic ? nil : { GitDragPayload.remoteBranch(item.fullPath, repositoryURL: repositoryURL) }))
            }
        }
        header(.stashes, expanded: sectionStates.stashesExpanded, target: .stashesHeader)
        if sectionStates.stashesExpanded {
            if stashEntries.isEmpty { empty(.stashes, loading: isLoadingStashes) }
            var occurrences: [String: Int] = [:]
            for entry in stashEntries {
                let identity = entry.objectID ?? entry.ref + "|" + entry.displayTitle
                let occurrence = occurrences[identity, default: 0]
                occurrences[identity] = occurrence + 1
                result.append(.init(id: .init(section: .stashes, kind: "entry", key: "\(identity):\(occurrence)"),
                    appearance: .init(title: entry.displayTitle, icon: "tray"), selection: .stash(entry.ref),
                    select: { stashSectionActions.select(.stash(entry.ref)) }, activate: { stashSectionActions.apply(entry.ref) },
                    menu: {
                        let menu = SidebarNativeMenu()
                        menu.item("Apply Stash") { stashSectionActions.apply(entry.ref) }
                        menu.item("Delete Stash") { stashSectionActions.delete(entry.ref) }
                        return menu
                    }, payload: { GitDragPayload.stash(entry.ref, repositoryURL: repositoryURL) }))
            }
        }
        if appState.showSubmodules {
            header(.submodules, expanded: sectionStates.submodulesExpanded, accessory: "plus", label: "Add Submodule") { _ in onRequestAddSubmodule() }
            if sectionStates.submodulesExpanded {
                if visibleSubmoduleRows.isEmpty { empty(.submodules, loading: isLoadingSubmodules) }
                for item in visibleSubmoduleRows {
                    if item.isFolder { result.append(folder(item, section: .submodules, expanded: expandedSubmoduleFolders, toggle: toggleSubmoduleFolder)); continue }
                    guard let entry = submoduleEntriesByPath[item.fullPath] else { continue }
                    result.append(.init(id: .init(section: .submodules, kind: "entry", key: entry.path),
                        appearance: .init(title: entry.name.split(separator: "/").last.map(String.init) ?? entry.name, subtitle: entry.path,
                            icon: entry.state.systemImage, badge: [entry.branch, entry.state.title].compactMap { $0 }.joined(separator: "  "), indent: item.indent),
                        selection: .submodule(entry.path), select: { submoduleSectionActions.select(.submodule(entry.path)) },
                        activate: { if SubmoduleSidebarPolicy.actions(for: entry).contains(.openInCommitPlus) { submoduleSectionActions.open(repositoryURL.appendingPathComponent(entry.path)) } },
                        menu: { nativeSubmoduleMenu(entry) }))
                }
            }
        }
        if appState.showSubtrees {
            header(.subtrees, expanded: sectionStates.subtreesExpanded, accessory: "plus", label: "Add/Link Subtree") { _ in onRequestAddLinkSubtree() }
            if sectionStates.subtreesExpanded {
                if subtreeEntries.isEmpty { empty(.subtrees, loading: isLoadingSubtrees) }
                for entry in subtreeEntries {
                    result.append(.init(id: .init(section: .subtrees, kind: "entry", key: entry.id),
                        appearance: .init(title: entry.name, subtitle: entry.path, icon: entry.folderExists ? "square.stack.3d.up.fill" : "exclamationmark.triangle.fill",
                            badge: [entry.squash ? "Squashed" : "", entry.folderExists ? "" : "Missing folder"].filter { !$0.isEmpty }.joined(separator: "  ")),
                        selection: .subtree(entry.id), select: { selection = .subtree(entry.id) }, menu: { nativeSubtreeMenu(entry) }))
                }
            }
        }
        return result
    }
}

/// Rich details are hosted only while their single popover is open.
@MainActor
enum SidebarNativePopover {
    private static var current: NSPopover?
    private static let lifecycle = Lifecycle()
    private final class Lifecycle: NSObject, NSPopoverDelegate {
        func popoverDidClose(_ notification: Notification) {
            if notification.object as? NSPopover === current { current = nil }
        }
    }
    static func show<Content: View>(_ content: Content, from view: NSView) {
        current?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = lifecycle
        popover.contentViewController = NSHostingController(rootView: content)
        current = popover
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
    }
}
