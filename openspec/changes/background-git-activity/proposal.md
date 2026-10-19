# Proposal

## Why

Almost every Git action in a repository window runs through `RepositoryOperationProgress`. That draws a dimmed full-window overlay, and the user can do nothing until the action finishes. For network-bound actions that never touch the index or working tree, such as fetch and push, this blocks the user for seconds or minutes with no benefit. These actions can safely run while the user keeps browsing history, staging, and committing.

## What Changes

- Add a per-window background activity lane for Git actions that are safe to run while the user keeps working. Initially these are user-initiated fetch (Fetch sheet, all remotes) and push (Push sheet, push tag, force-push tag after its existing confirmation). Actions in the lane no longer show the global overlay.
- Run actions in the lane one at a time per repository, so two remote operations never race for the same ref locks. Foreground actions that also update remote-tracking refs (pull, update current branch, fetch and fast-forward a branch, undo/redo of remote entries) wait for the lane to drain before they start.
- Make the repository-name component in the window header (provider icon plus repository name, separate from the notification bell) show activity state: the provider icon becomes a spinner while background actions run, and a red error icon when one has failed.
- Clicking the repository-name component opens a popover that lists running, queued, and failed background actions. A failed item shows a short error message and a **View** button that opens a modal with the full error detail. Successful items remove themselves. Failed items stay until the user dismisses them.
- Background failures are shown in the popover instead of the blocking `Error` alert.
- Keep the global overlay unchanged for every action that writes the index, working tree, or `HEAD` (commit, checkout, merge, rebase, pull, stash, reset, cherry-pick, revert, undo/redo, custom actions, Git Flow, submodule and subtree operations, Repository AI mutations).
- Background fetch and push no longer set the `SyncState` flags that disable local actions, so commit, stage, stash, and branch actions stay available while they run.
- Background status reads that follow a background action use `GIT_OPTIONAL_LOCKS=0`, so they do not take `index.lock` while the user stages or commits.

## Capabilities

### New Capabilities

- `background-git-activity`: classifying Git actions as background-safe or blocking, running background-safe actions per repository window without the global overlay, the header activity indicator, the activity popover, and the error detail modal.

### Modified Capabilities

None. `openspec/specs/` has no existing capabilities.

## Impact

- `macgit/App/RepositoryOperationProgress.swift`: stays as the blocking lane. A sibling background activity model sits next to it.
- `macgit/Services/SyncState.swift`: `performFetch`/`performPush` need a mode that reports errors to the caller instead of `showError`, and that does not set `isFetching`/`isPushing` (which feed `isAnySyncing`).
- `macgit/Views/MainWindow/MainWindowView.swift`, `MainWindowView+Sheets.swift`, `MainWindowView+ProviderAccountPreferences.swift`: route fetch and push through the background lane, and replace the principal toolbar item (`repoIconName` + name + `GitHubNotificationBell`) with an interactive repository-name component.
- New views under `macgit/Views/MainWindow/` for the activity popover and the error detail sheet.
- `macgit/Services/GitStatusService+Status.swift`: optional-locks environment for refresh status reads.
- Tests: `RepositoryOperationProgressTests` (existing) plus new unit tests for the background lane. No Firebase, plan gating, or synced-settings changes.
