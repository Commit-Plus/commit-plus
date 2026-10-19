# Proposal

## Why

`background-remote-branch-delete` covered the Delete Branches sheet. Two remote paths still behave the old way. First, the sidebar context-menu deletes (a local branch with "Also delete remote branch", or a single remote branch) still block the window for the network round trips. Second, undo and redo of remote branch entries (`.pushBranch`, `.deleteRemoteBranch` in `GitUndoExecutor`) run plain `git push`/`git ls-remote` without the connected GitHub or GitLab token, so they can fail on token-only HTTPS remotes even though the original delete or publish succeeded.

## What Changes

- Sidebar "Delete branch" with the remote option: the local delete stays under the brief overlay, and the remote delete becomes a background item (`Deleting <remote>/<branch>`) through the same remote phase the sheet uses, with the same undo rules.
- Sidebar "Delete remote branch": runs fully as a background item. On success, selection of that remote branch falls back to History.
- Undo and redo of remote-only entries (operations that contact a remote and otherwise only touch branch, tag, or upstream refs, such as undo of delete branch, publish, or force push) run as background items instead of under the overlay. Undo of commits, checkouts, resets, pulls, stashes, and similar actions keeps blocking, because those write the index, working tree, or HEAD.
- Undo and redo whose operations contain `.pushBranch` or `.deleteRemoteBranch` resolve the window's provider credentials first. If the user cancels account selection, the entry is restored. `GitUndoExecutor` then runs those operations with credential injection.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `branch-deletion`: provider credentials now also cover remote undo/redo operations, and the two-phase behavior extends to the sidebar delete commands.
- `background-git-activity`: the list of background-safe actions gains the sidebar remote branch deletes, and a new requirement makes remote-only undo and redo run in the background.

## Impact

- `macgit/Views/MainWindow/SidebarView+BranchActions.swift`, `Sidebar/SidebarBranchPresentationModifier.swift`: route through `GitStatusService.deleteLocalBranches` and `onRunBackgroundRemoteBranchDeletion`.
- `macgit/Views/MainWindow/MainWindowView+BranchDeletion.swift`: selection fallback after a remote-only delete succeeds.
- `macgit/Services/GitUndoExecutor.swift`, `GitStatusService+Branch.swift` (credentialed refspec push), `MainWindowView+MenuActions.swift` (`executeUndoEntry` resolves credentials).
- Tests: `GitUndoRemoteIntegrationTests`, `GitBranchDeletionIntegrationTests`.
