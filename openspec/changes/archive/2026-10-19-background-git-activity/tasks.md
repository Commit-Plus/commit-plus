# Tasks

## 1. Background lane in RepositoryOperationProgress

- [x] 1.1 Add `RepositoryBackgroundActivityItem` (id, title, state `.queued/.running/.failed(summary:detail:)`), `RepositoryBackgroundActivityOutcome`, and the derived `backgroundIndicator` (`.idle/.running/.failed`, running wins) to `macgit/App/RepositoryOperationProgress.swift`. Verify that the app target compiles.
- [x] 1.2 Implement `runInBackground(title:operation:)` with a single FIFO drain task, plus `dismissBackgroundItem(id:)`, `waitForBackgroundIdle()` (cancellation-aware), and `cancelAllBackground()`. Success removes the item, failure keeps it with a summary (first non-empty line, about 140 chars) and the full detail. `activeOperation` must not change. Verify with new cases in `RepositoryOperationProgressTests`: FIFO order, at most one running item, success removal, failure retention, dismiss, idle wait resumes after drain, cancel-all clears items, `activeOperation` stays nil during background work.

## 2. SyncState background variants

- [x] 2.1 Refactor `SyncState.performFetch` into a shared helper and add `performBackgroundFetch(...) -> RepositoryBackgroundActivityOutcome`. It must not set `isFetching`, must not call `showError`, and must refresh and post the remote-refs notifications after full or partial success (`GitFetchError.succeededRemotes`). Verify with a new `SyncStateBackgroundRemoteIntegrationTests` using a temporary repo and bare remote: success returns `.succeeded` and updates remote refs, a missing remote returns `.failed` with git's message, `isAnySyncing`/`showingError` stay false, and partial success refreshes `origin` and fails for the bad remote.
- [x] 2.2 Do the same for `performPush` → `performBackgroundPush(...)`. Keep the `checkConflicts` preflight (it now reports failure), `pushErrorMessage`, and publish undo registration after success. Verify in `SyncStateBackgroundRemoteIntegrationTests`: a push publishing a new branch registers the `Publish <remote>/<branch>` undo entry, a rejected non-fast-forward push returns `.failed` with no undo entry, and `isPushing` stays false.

## 3. Status reads without optional locks

- [x] 3.1 Pass `GIT_OPTIONAL_LOCKS=0` in `status(for:)` and `trackedStatusCounts(in:)` (`GitStatusService+Status.swift`), following `GitStatusService+WelcomeAttention.swift`. Verify with a case in the existing `GitStatusServiceStatusTests` (temporary repos): holding a pre-created `.git/index.lock` does not make `status(for:)` fail, and output matches the run without the lock.

## 4. Routing actions to the right lane

- [x] 4.1 Add `runBackgroundRemoteOperation(_:remotes:operation:)` next to `runRemoteOperation` (`MainWindowView+ProviderAccountPreferences.swift`). It resolves credentials first, then calls `operationProgress.runInBackground`. Verify that the app target compiles.
- [x] 4.2 Route `fetchSheet` (`MainWindowView+Sheets.swift`), `pushSheet`, sidebar push tag, and the force-push tag confirmation (`MainWindowView.swift`) to the background lane with the `SyncState` background variants. Verify by grep that these call sites no longer use `runRepositoryOperation`/the foreground lane.
- [x] 4.3 Make the foreground remote-ref actions (pull from sheet, pull remote branch, pull tracked, fetch-and-fast-forward branch, current-branch update) and undo/redo execution `await operationProgress.waitForBackgroundIdle()` inside their foreground operation. Verify by code review that each call site waits before its git work and that cancel on the overlay ends the wait.
- [x] 4.4 Call `operationProgress.cancelAllBackground()` from `MainWindowView` `onDisappear`. Verify that it is covered by the cancel-all unit test from 1.2 and by the manual check in 6.1.

## 5. Header indicator, popover, and error detail

- [x] 5.1 Add `macgit/Views/MainWindow/RepositoryActivityHeaderButton.swift`: a plain button with the provider icon, a small spinner, or a red `exclamationmark.circle.fill` (per `backgroundIndicator`) and the repository name, scaled by `appState.textSize`, with an accessibility label and help text, presenting the popover from local state. Replace the icon and name in the `.principal` toolbar item, keeping `GitHubNotificationBell()` as a separate sibling. Verify that the app target compiles.
- [x] 5.2 Add `RepositoryBackgroundActivityPopover` (rows for queued, running, and failed items; failed rows have a summary, a **View** button, and dismiss; empty state). Verify that the app target compiles.
- [x] 5.3 Add `RepositoryBackgroundErrorDetailSheet` (selectable monospaced full text, Copy, Close), presented from `MainWindowView` via `.sheet(item:)` after closing the popover. Verify with `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.

## 6. Integration validation

- [x] 6.1 Manual UI review in the running app. Fetch and push run without the overlay, and committing or staging works meanwhile. The header shows the spinner, then the provider icon on success. A rejected push (or a fetch with an unreachable remote) shows the red icon, the popover summary, and the detail modal with Copy, and dismiss restores the icon. Pull started during a push waits behind the overlay. Two repository windows stay independent. Closing a window with a running fetch does not crash. The bell still opens its own popover. Header layout is balanced at narrow and wide window widths, in light and dark mode. (2026-10-19: user verified fetch/push without overlay, commit during background work, red error state, popover/detail, bell and header layout. Queued state, pull waiting, two windows, and closing during fetch were not tested; deferred by user until reported.)
- [x] 6.2 Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/RepositoryOperationProgressTests -only-testing:macgitTests/SyncStateBackgroundRemoteIntegrationTests -only-testing:macgitTests/GitStatusServiceStatusTests -only-testing:macgitTests/PushSheetViewTests -only-testing:macgitTests/BranchFetchActionTests test` and report the results.
- [x] 6.3 Run `git diff --check` and verify that there are no whitespace errors.
