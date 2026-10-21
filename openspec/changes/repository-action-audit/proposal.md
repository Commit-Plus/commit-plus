# Proposal

## Why

The header activity popover only shows background-lane work while it runs or fails, so once an action finishes there is no way to see which Git commands the app actually ran on a repository or what Git answered. Users who want to understand what a fetch, push, commit, or automatic fetch did (or why it silently did nothing) need a per-session audit of the app's Git actions, without the audit growing the app's memory footprint over a long session.

## What Changes

- The repository activity popover (opened from the repository name in the window header) gets two tabs: **Audit** and **Background**.
- **Background** keeps today's content and behavior: the transient automatic-fetch row plus the window's queued, running, and failed background-lane items with View and dismiss.
- **Audit** is a split view. The left list shows the mutating Git actions run for this repository during the current app session, newest first: a short title (for example `Fetch origin`), a one-line result summary, the time, a failure marker, and a small pill marking whether the action came from the **User** or from the **System** (for example an automatic fetch). The right pane shows the selected action's command (`$ git fetch --prune origin`) with credentials redacted, its status and timestamp, and its full (bounded) output.
- Mutating Git commands (fetch, push, pull, commit, checkout, merge, rebase, reset, revert, cherry-pick, stash, tag/branch/remote/worktree/submodule/config writes, add/rm/apply, and similar) are recorded when they finish. Read-only queries (status, log, diff, rev-parse, for-each-ref, …) are not recorded.
- Audit records are stored in a dedicated session SQLite database on disk, not kept in memory. The list loads summaries only; a command's output is read when it is selected. Output per command and rows per repository are capped.
- The audit is session-scoped: it is cleared when the app launches and when it terminates, so it only ever covers the current app run.
- This does not adopt a combined All/User/Background filter; origin is shown per item instead.

## Capabilities

### New Capabilities
- `git-action-audit`: Session-scoped recording of the app's mutating Git commands per repository (command, origin, result, output), its storage and lifetime, and the Audit tab that presents it.

### Modified Capabilities
- `background-git-activity`: The "Repository name opens the activity popover" requirement changes: the popover is now tabbed (Audit and Background), and the background-lane list moves into the Background tab.

## Impact

- `macgit/Views/MainWindow/RepositoryBackgroundActivityPopover.swift`, `RepositoryActivityHeaderButton.swift`, and the toolbar construction in `MainWindowView.swift` (pass the repository URL).
- `macgit/Services/GitStatusService.swift` process layer (`GitProcessExecution`, `runGitRaw`, `runGitBounded`) and the `applyPatch` path in `GitStatusService+Stage.swift`; `GitCommandLogStore` argument sanitizing becomes shared.
- `macgit/Services/SyncState.swift` marks automatic fetches as system-originated.
- New session audit store (SQLite, separate file under Application Support) and lifecycle hooks in `MacgitApplicationDelegate`.
- No Firebase, synced-settings, plan-gating, or undo changes. No new dependencies (uses the system SQLite3 module already in use).
