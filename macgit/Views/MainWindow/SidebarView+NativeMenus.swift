// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

extension SidebarView {
    func nativeBackgroundMenu() -> NSMenu {
        let menu = SidebarNativeMenu()
        menu.item("Add Submodule...", onRequestAddSubmodule)
        menu.item("Add/Link Subtree...", onRequestAddLinkSubtree)
        menu.separator()
        menu.item("New Branch...", onRequestCreateBranch)
        menu.item("New Tag...", onRequestCreateTag)
        menu.separator()
        menu.item("Show Tags", checked: appState.showTags) { appState.showTags.toggle() }
        menu.item("Show Worktrees", checked: appState.showWorktrees) { appState.showWorktrees.toggle() }
        menu.item("Show Submodules", checked: appState.showSubmodules) { appState.showSubmodules.toggle() }
        menu.item("Show Subtrees", checked: appState.showSubtrees) { appState.showSubtrees.toggle() }
        return menu
    }

    func nativeBranchMenu(_ branch: String) -> NSMenu {
        let menu = SidebarNativeMenu()
        let actions = branchSectionActions
        let upstream = upstreamByBranch[branch]
        let remotes = BranchUpstreamActionPolicy.pushRemotes(branch: branch, upstream: upstream, remotes: remoteNames)
        menu.item("Checkout \(branch)", enabled: branch != currentBranch) { actions.checkout(branch) }
        menu.separator()
        menu.item("Merge \(branch) into \(currentBranch)", enabled: branch != currentBranch) { actions.mergeIntoCurrent(branch) }
        menu.item("Rebase current changes onto \(branch)", enabled: branch != currentBranch) { actions.rebaseOnto(branch) }
        menu.separator()
        menu.item("Fetch \(branch)", enabled: BranchFetchActionPolicy.shouldEnableFetch(for: branchSyncStatus[branch])) { actions.fetch(branch) }
        menu.item(upstream.map { "Pull \($0) (tracked)" } ?? "Pull (tracked)", enabled: BranchUpstreamActionPolicy.shouldEnablePullFromUpstream(for: upstream)) { actions.pullTracked(branch) }
        menu.submenu("Push to") { push in
            push.item(upstream.map { "\($0) (tracked)" } ?? "Push to (tracked)", enabled: BranchUpstreamActionPolicy.shouldEnablePushToUpstream(for: upstream)) { actions.pushTracked(branch) }
            if !remotes.isEmpty {
                push.submenu("Other Remote") { other in
                    for remote in remotes { other.item(remote) { actions.pushToRemote(branch, remote) } }
                }
            }
            if upstream?.isEmpty == false || !remotes.isEmpty { push.separator() }
            if let upstream, !upstream.isEmpty { push.item("Force Push to \(upstream) (tracked)…") { actions.forcePushTracked(branch) } }
            if !remotes.isEmpty {
                push.submenu("Force Push to Other Remote") { other in
                    for remote in remotes { other.item("\(remote)/\(branch)…") { actions.forcePushToRemote(branch, remote) } }
                }
            }
        }
        menu.lazySubmenu("Track Remote Branch", enabled: !remoteNames.isEmpty) { tracking in
            var count = 0
            for remote in remoteNames.sorted() {
                for name in (branchesByRemote[remote] ?? []).sorted() {
                    let ref = "\(remote)/\(name)"
                    tracking.item(ref, checked: ref == upstream) { actions.trackRemoteBranch(branch, ref) }
                    count += 1
                }
            }
            if count == 0 { tracking.item("No remote branches", enabled: false) {} }
            tracking.separator()
            tracking.item("(None)", checked: upstream == nil) { actions.trackRemoteBranch(branch, nil) }
        }
        menu.separator()
        menu.item("Create Branch from '\(branch)'...") { actions.createBranchFrom(branch) }
        menu.item("Create Tag from '\(branch)'...") { actions.createTagFrom(branch) }
        menu.separator()
        menu.item("Compare with…") { actions.compare(branch) }
        menu.separator()
        menu.item("Rename...") { actions.rename(branch) }
        menu.item("Delete \(branch)", enabled: branch != currentBranch) { actions.confirmDelete(.single(branch)) }
        menu.separator()
        menu.copy("Copy Branch Name to Clipboard", value: branch)
        menu.separator()
        menu.item("Create Pull Request...", enabled: BranchUpstreamActionPolicy.shouldEnableCreatePullRequest(for: upstream)) { actions.createPullRequest(branch) }
        return menu
    }

    func nativeTagMenu(_ name: String) -> NSMenu {
        let menu = SidebarNativeMenu(), actions = tagSectionActions
        menu.copy("Copy Tag Name to Clipboard", value: name)
        menu.separator()
        menu.item("Checkout \(name)") { actions.checkout(name) }
        menu.item("Details...") { actions.showDetails(name) }
        menu.separator()
        menu.item("Diff Against Current") { actions.diffAgainstCurrent(name) }
        menu.separator()
        menu.submenu("Push to") { sub in
            for remote in remoteNames.sorted() { sub.item(remote) { actions.pushToRemote(name, remote) } }
        }
        menu.submenu("Force Push to") { sub in
            for remote in remoteNames.sorted() { sub.item(remote) { actions.forcePushToRemote(name, remote) } }
        }
        menu.item("Delete \(name)") { actions.delete(name) }
        return menu
    }

    func nativeRemoteMenu(_ fullPath: String) -> NSMenu {
        let menu = SidebarNativeMenu(), actions = remoteSectionActions
        let parts = fullPath.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { menu.copy("Copy Branch Name to Clipboard", value: fullPath); return menu }
        let remote = parts[0], branch = parts[1], symbolic = branch == "HEAD"
        menu.item("Checkout...", enabled: !symbolic) { actions.select(.remoteBranch(fullPath)); actions.checkoutFromContextMenu(fullPath) }
        menu.item("Pull \(fullPath) into \(currentBranch.isEmpty ? "current branch" : currentBranch)", enabled: !symbolic && !currentBranch.isEmpty) { actions.pullIntoCurrent(remote, branch) }
        menu.separator()
        menu.copy("Copy Branch Name to Clipboard", value: fullPath)
        menu.item("Compare with…", enabled: !symbolic) { actions.compare(fullPath) }
        menu.separator()
        menu.item("Delete...", enabled: !symbolic) { actions.confirmDelete(.init(remote: remote, branch: branch)) }
        menu.separator()
        menu.item("Create Pull Request...", enabled: !symbolic) { actions.createPullRequest(remote, branch) }
        return menu
    }

    func nativeWorktreeMenu(_ entry: WorktreeEntry) -> NSMenu {
        let menu = SidebarNativeMenu(), actions = worktreeSectionActions
        menu.item("Open in New Window") { onRequestOpenWorktree(entry.path) }
        menu.item("Open in Terminal") { actions.openInTerminal(entry.path) }
        menu.separator()
        menu.item(entry.label?.isEmpty == false ? "Edit Label..." : "Set Label...") { actions.editLabel(entry) }
        if entry.label?.isEmpty == false { menu.item("Clear Label") { actions.clearLabel(entry) } }
        if entry.path.standardizedFileURL != repositoryURL.standardizedFileURL {
            menu.separator()
            if entry.isLocked { menu.item("Unlock") { actions.unlock(entry) } }
            else { menu.item("Lock...") { actions.editLock(entry) } }
            menu.item("Rename/Move...") { actions.move(entry) }
            menu.item("Switch Branch...") { actions.switchBranch(entry) }
            menu.separator()
            menu.item("Remove Worktree...") { actions.confirmRemoval(entry) }
        }
        menu.separator()
        menu.copy("Copy Path", value: entry.path.path)
        return menu
    }

    func nativeSubmoduleMenu(_ entry: GitSubmoduleEntry) -> NSMenu {
        let menu = SidebarNativeMenu(), actions = submoduleSectionActions
        let allowed = SubmoduleSidebarPolicy.actions(for: entry)
        let path = repositoryURL.appendingPathComponent(entry.path)
        if allowed.contains(.openInCommitPlus) { menu.item("Open in Commit+") { actions.open(path) } }
        if allowed.contains(.showInFinder) { menu.item("Show in Finder") { actions.showInFinder(path) } }
        if allowed.contains(.openInTerminal) { menu.item("Open in Terminal") { actions.openInTerminal(path) } }
        if allowed.contains(.initialize) { menu.item("Initialize") { actions.initialize(entry.path) } }
        if allowed.contains(.updateToRecordedCommit) { menu.item("Update to Recorded Commit") { actions.update(entry.path, .recordedCommit) } }
        if allowed.contains(.updateFromRemote) { menu.item("Update from Remote...") { actions.update(entry.path, .remoteCheckout) } }
        if allowed.contains(.synchronizeURL) { menu.item("Synchronize URL") { actions.synchronizeURL(entry.path) } }
        if allowed.contains(.editSettings) { menu.item("Edit Submodule Settings...") { actions.edit(entry) } }
        if allowed.contains(.deinitialize) { menu.item("Deinitialize...") { actions.deinitialize(entry) } }
        if allowed.contains(.remove) { menu.item("Remove Submodule...") { actions.remove(entry) } }
        return menu
    }

    func nativeSubtreeMenu(_ entry: GitSubtreeEntry) -> NSMenu {
        let menu = SidebarNativeMenu(), actions = subtreeSectionActions
        let allowed = SubtreeSidebarPolicy.actions(for: entry)
        let path = repositoryURL.appendingPathComponent(entry.path)
        if allowed.contains(.showInFinder) { menu.item("Show in Finder") { actions.showInFinder(path) } }
        if allowed.contains(.openInTerminal) { menu.item("Open in Terminal") { actions.openInTerminal(path) } }
        if allowed.contains(.pull) { menu.item("Pull from Subtree Remote...") { actions.pull(entry) } }
        if allowed.contains(.push) { menu.item("Push to Subtree Remote...") { actions.push(entry) } }
        if allowed.contains(.editLink) { menu.item("Edit Link...") { actions.edit(entry) } }
        if allowed.contains(.unlink) { menu.item("Unlink...") { actions.unlink(entry) } }
        return menu
    }

    func nativeGitFlowMenu() -> NSMenu {
        let menu = SidebarNativeMenu(), state = gitFlowCommandState
        if state.isEnabled {
            if state.hasPendingFinish {
                menu.item("Resume Finish", enabled: state.canResumeOrAbortFinish) { performGitFlowAction(.resumeFinish) }
                menu.item("Abort Finish", enabled: state.canResumeOrAbortFinish) { performGitFlowAction(.abortFinish) }
                menu.separator()
            }
            for kind in GitFlowTopicKind.allCases {
                menu.item("Start \(kind.displayName)…", enabled: state.canStart(kind)) { performGitFlowAction(.start(kind)) }
                menu.item("Finish \(kind.displayName)…", enabled: state.canFinish(kind)) { performGitFlowAction(.finish(kind)) }
                menu.separator()
            }
            menu.item("Configure Git Flow…", enabled: state.canConfigure) { performGitFlowAction(.configure) }
            menu.item("Disable Git Flow", enabled: !state.operationInProgress) { performGitFlowAction(.disable) }
        } else { menu.item("Set Up Git Flow…", enabled: state.canConfigure) { performGitFlowAction(.configure) } }
        return menu
    }
}
