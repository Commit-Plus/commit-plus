# Proposal

## Why

Deleting several branches from the Delete Branches sheet blocks the whole repository window until every step finishes. With "Also delete matching remote branches", or when remote branches are selected, each branch costs two network round trips (`git ls-remote` to capture the hash for undo, then `git push --delete`). The overlay can stay up for a long time, while the local part (`git branch -d/-D`) finishes in milliseconds. `background-git-activity` already gives each window a non-blocking lane for remote operations, but branch deletion does not use it.

## What Changes

- Split batch branch deletion into two phases:
  - **Local phase:** stays foreground, under the existing overlay. It covers local branch deletes, merged-branch validation, and capturing each branch's tip and upstream.
  - **Remote phase:** a single item in the window's background lane. It captures the remote hash and runs `git push --delete` for each remote target, covering both matching remotes of deleted local branches and remote branches selected directly.
- The Delete Branches sheet closes when the local phase succeeds. If a local delete fails, the sheet stays open and shows the existing failure alert for local failures only. Remote work for the branches that were deleted locally is still queued.
- The background item is titled `Deleting <remote>/<branch>` for one target and `Deleting N remote branches` for several. If any target fails, the item becomes a failed popover entry: the summary counts the failures and the detail lists each branch with its error.
- Undo entries for a local branch that also had a remote target are registered when its remote deletion finishes. The entry covers both local and remote when the remote delete succeeded, and only the local branch when it failed. Branches without a remote target get their undo entry immediately after the local phase, as today. Directly selected remote branches still have no undo entry, unchanged.
- Remote branch deletion and its hash lookup inject the window's provider credentials, as push and fetch already do. Today `GitStatusService.deleteRemoteBranch` runs plain `git push --delete` without the connected GitHub or GitLab token.
- Move the deletion coordination out of `BranchSheetView` so the background phase does not depend on the sheet staying alive.

## Capabilities

### New Capabilities

- `branch-deletion`: behavior of deleting local and remote branches from the Delete Branches sheet: the two phases, failure reporting, undo registration, and credential use for remote deletes.

### Modified Capabilities

- `background-git-activity`: the list of background-safe actions in "Background-safe actions do not block the window" gains remote branch deletion from the Delete Branches sheet.

## Impact

- `macgit/Views/Common/BranchSheetView.swift`: the deletion loop and `registerDeletedBranchUndo` move out. The sheet keeps selection UI, confirmation, and local-failure alerts, and receives a background-remote-operation runner.
- `macgit/Services/SyncState.swift`: new local-phase and background-remote-phase methods, following `performBackgroundPush`.
- `macgit/Services/GitStatusService+Branch.swift`: `deleteRemoteBranch` gains a credential resolver, plus a credentialed remote branch hash lookup.
- Hosts of `BranchSheetView` that must pass the background runner: `MainWindowView+Sheets.swift`, `Sidebar/SidebarBranchPresentationModifier.swift` (merged and prefix deletion), `Sidebar/SidebarDeletePrefixSheet.swift`, and the `SidebarView` plumbing.
- Tests: new branch deletion integration tests plus the existing `BranchSheetInitialStateTests`.
- No Firebase, plan gating, or synced settings impact.
