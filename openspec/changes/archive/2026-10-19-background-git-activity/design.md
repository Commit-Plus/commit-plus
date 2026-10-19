# Design

## Context

- `RepositoryOperationProgress` (`macgit/App/RepositoryOperationProgress.swift`) is a `@MainActor ObservableObject`, created as a `@StateObject` in `ContentView` and handed to `MainWindowView`. That makes it one instance per repository window. `run(message:operation:)` publishes `activeOperation`, and `MainWindowView.mainLayout` draws `RepositoryOperationOverlayView` whenever that value is non-nil. Many command guards also check `operationProgress.activeOperation == nil`.
- `SyncState` (`macgit/Services/SyncState.swift`) is also one per window (`@StateObject` in `MainWindowView`). `performFetch` and `performPush` set `isFetching`/`isPushing`, which feed `isAnySyncing`, and they report failures through `showError` (the blocking `Error` alert).
- Fetch is started from `fetchSheet` (`MainWindowView+Sheets.swift`) via `runRepositoryOperation`. Push starts from `pushSheet`, sidebar push tag, and the force-push tag confirmation (`MainWindowView.swift`), all via `runRemoteOperation` (`MainWindowView+ProviderAccountPreferences.swift`). That function resolves credentials first, then calls `runRepositoryOperation`.
- The header is the `.principal` `ToolbarItem` in `MainWindowView.toolbarContent`: `Image(repoIconName)`, the repository name `Text`, and `GitHubNotificationBell()`.
- The automatic background fetch in `SyncState.startBackgroundSync` already runs without the overlay and silently ignores failures.
- Refresh status reads (`GitStatusService+Status.swift`: `status(for:)`, `trackedStatusCounts`) run plain `git status`. That can opportunistically write `.git/index`, taking `index.lock`.

## Goals / Non-Goals

**Goals:**
- Add a second, non-blocking lane to the existing per-window progress object, and route fetch and push through it.
- Keep every other caller and guard of `activeOperation` unchanged.

**Non-Goals:**
- Making pull, update current branch, fetch-and-fast-forward, or local mutations background-capable. These can touch the working tree or `HEAD`.
- Cancel buttons for individual background items. Closing the window cancels them all. Per-item cancel can be added later without changing the lane.
- Showing the automatic background fetch in the popover. It stays silent, as it is today.
- Moving Repository AI remote operations (`RepositoryAIRemoteOperationExecutor`) to the background lane. They keep their own overlay usage.
- Changing the unused, unscoped `RepositoryOperationProgressBus`.

## Decisions

### 1. `RepositoryOperationProgress` owns the background lane

The lane is added to `RepositoryOperationProgress` instead of a new controller:

- `@Published private(set) var backgroundItems: [RepositoryBackgroundActivityItem]` (id, title, state `.queued | .running | .failed(summary:, detail:)`).
- `runInBackground(title:operation:)`, where `operation` is `() async -> RepositoryBackgroundActivityOutcome` (`.succeeded` or `.failed(Error/String)`). It appends a queued item and starts a single drain `Task` if none is running. The drain runs items FIFO, one at a time. On success it removes the item; on failure it keeps the item as `.failed`.
- `dismissBackgroundItem(id:)`, `waitForBackgroundIdle() async` (resumes stored continuations when the queue empties), and `cancelAllBackground()`.
- A derived `backgroundIndicator: .idle | .running | .failed`. Running wins over failed, matching the spec.

**Why:** The project rules ask to extend the existing owner. The object is already per-window, already injected wherever operations start, and already the source of truth for "is something running". `activeOperation` is left untouched, so all existing guards keep blocking only on the foreground lane.

**Alternative:** a separate `BackgroundGitActivityController`. It was rejected because it would duplicate task and cancel bookkeeping and need new injection paths.

### 2. One-at-a-time lane per window

Background items run serially within a window. Fetch and push both write `refs/remotes/*` and `FETCH_HEAD`/ref lock files, and running them concurrently produces `cannot lock ref` errors with no user benefit, since the network is the bottleneck. The user-facing parallelism this change targets is between background actions and the user's own local work.

### 3. Foreground remote-ref actions wait for the lane

`runRemoteOperation` gains a lane parameter. Callers for pull, pull tracked, pull remote branch, fetch-and-fast-forward, and current-branch update keep the foreground lane, and their operation closure first does `await operationProgress.waitForBackgroundIdle()`. Since this happens inside the foreground `run`, the overlay shows their message while they wait. Undo/redo execution (`MainWindowView` confirmed undo and `executeUndoEntry`) waits the same way, because redo of a publish or undo of a remote branch updates remote refs.

**Alternative:** rejecting these actions with an info message while the lane is busy. This is simpler, but the user would have to retry by hand.

### 4. `SyncState` background variants return their outcome

Add `performBackgroundFetch(options:repositoryURL:credentialResolver:) async -> RepositoryBackgroundActivityOutcome` and `performBackgroundPush(...)`. They share the existing body through private helpers that take an error-reporting closure and a `setsSyncFlags: Bool`. The background variants:

- do not set `isFetching`, `isPushing`, or `activeSyncBranch`, so `isAnySyncing` stays false and local actions stay enabled;
- return the failure instead of calling `showError`. Push uses `SyncState.pushErrorMessage`, and partial fetch success (`GitFetchError.succeededRemotes`) still refreshes before returning failure;
- keep the existing `refresh`, `repositoryDidChange`/`repositoryRemoteRefsDidRefresh` posts, and undo registration after success (`GitUndoManager.register` on the main actor).

The existing foreground `performFetch`/`performPush` keep their signatures for other callers (Repository AI, Git Flow).

### 5. Routing in `MainWindowView`

- `fetchSheet`: resolve credentials (unchanged), then `operationProgress.runInBackground(title: "Fetching remotes")`.
- `pushSheet`, sidebar push tag, and force-push tag confirmation: `runRemoteOperation(..., lane: .background)`. Credential resolution, including any reconnect UI, still happens before the item is queued.
- `checkConflicts` stays inside `performPush` as a preflight. If it returns early, it reports a failure ("Resolve conflicts before pushing").
- Force push of branches (`MainWindowView+BranchForcePush.swift`) stays foreground in this change. It is guarded by `isAnySyncing` and has its own confirmation flow, and can move later.

### 6. Header component and popover (window scoping)

The `.principal` item becomes `HStack { RepositoryActivityHeaderButton(...); GitHubNotificationBell() }`:

- `RepositoryActivityHeaderButton` (new, `macgit/Views/MainWindow/RepositoryActivityHeaderButton.swift`) is a plain-style `Button` that shows the provider icon, a small `ProgressView`, or `exclamationmark.circle.fill` in red, depending on `backgroundIndicator`, followed by the repository name. It uses a local `@State isPresented` for `.popover`. It has an accessibility label and help text ("Background Git activity").
- `RepositoryBackgroundActivityPopover` (new) lists items with a title, a state glyph, and for failures the one-line summary, a **View** button, and a dismiss (`xmark`) button. It shows an empty state when there are no items.
- **View** calls back to `MainWindowView`, which sets `@State backgroundErrorDetail: RepositoryBackgroundActivityItem?` and closes the popover. `.sheet(item:)` then presents `RepositoryBackgroundErrorDetailSheet`: a monospaced, selectable scroll view with Copy and Close buttons.

**Window scoping:** all of this reads the window's own `operationProgress` instance passed in from `MainWindowView`. No `NotificationCenter` or `FocusedValues` routing is added, so another window's activity cannot leak in. `MainWindowView.onDisappear` calls `operationProgress.cancelAllBackground()`.

The short summary is the first non-empty line of the error text, truncated to about 140 characters. The detail is the full text.

### 7. Optional locks for refresh status reads

`status(for:)` and `trackedStatusCounts(in:)` pass an environment with `GIT_OPTIONAL_LOCKS=0`, following `GitStatusService+WelcomeAttention.swift`. This applies to every refresh, not just background-triggered ones. The periodic auto-refresh already races with user staging in the same way, and `--no-optional-locks` changes no output.

## Risks / Trade-offs

- [Without opportunistic index refresh, large repositories can have slower repeated `git status`] → Mutating commands (add, commit, checkout) still refresh the index. Measure on a large repository during manual review.
- [User pushes a branch and then amends or rebases it while the push is queued] → Git pushes the ref value at execution time, and the push either sends the new tip or is rejected as non-fast-forward. The failure appears in the popover. This is acceptable and matches CLI behavior.
- [User deletes a local branch that a queued push names] → The push fails with git's error in the popover. No data loss.
- [Foreground pull waits behind a slow background push and seems stuck] → The overlay message stays visible and the existing Cancel cancels the waiting task. The wait is cancellation-aware.
- [Background undo registration lands while the user is mid-undo] → Undo execution waits for the lane (Decision 3), so registration and undo never interleave.
- [Popover items are lost when the window closes] → This is intended, per spec. Running work is cancelled with the window.

## Migration Plan

Client-only change with no persisted state, synced settings, Firebase contract, or plan gating. To roll back, revert the routing in `MainWindowView`. The lane is additive.
