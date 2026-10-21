# Design

## Context

- All app Git commands go through `actor GitStatusService`. Real processes are spawned by `GitProcessExecution` from `runGitRaw` and `runGitBounded` (`runGit` and `runRemoteGit` delegate to `runGitRaw`); `applyPatch` in `GitStatusService+Stage.swift` spawns its own `Process` for `git apply`. The `GitCommandRunning` test seam bypasses the process layer.
- `GitProcessExecution.finish` discards stderr on success. Git writes fetch/push results (`From …`, `To …`, ref updates) to stderr, so the success output a user wants to see is currently lost.
- `GitCommandLogStore` already sanitizes arguments (tokens, passwords, auth headers, URL user info) for the opt-in verbose log; its helpers are private.
- Automatic fetches run through `SyncState.performAutomaticFetch`, which calls `GitStatusService.fetch(options:…)` per remote. User fetch/push go through `performFetch`/`performBackgroundFetch`/`performPush`/… and the same service methods.
- `LocalSQLiteDatabase` is the durable user-data store (key/payload rows, schema version 1, opens a connection per call). It is not a good fit for a high-write, throwaway log.
- The popover is `RepositoryBackgroundActivityPopover`, presented by `RepositoryActivityHeaderButton`, which `MainWindowView.toolbarContent` builds per window. The button does not currently know the repository URL.

## Goals / Non-Goals

**Goals:**
- Capture every mutating command in one place, with no per-call-site wiring, so new features are audited automatically.
- Keep memory flat during long sessions: rows live on disk; the UI holds one page of summaries and one selected output.
- Keep recording off the critical path and failure-tolerant: an audit write failure never fails or delays a Git operation.

**Non-Goals:**
- Grouping several commands into one higher-level action (for example a push of three branches stays three records).
- Auditing processes that bypass `GitStatusService`: custom actions (user scripts via `CustomActionExecutor`), `nonisolated` helpers that run `/usr/bin/git` directly (for example `configuredSubmodulePaths`, which is read-only), and the `GitCommandRunning` test seam.
- Persisting audit across launches, exporting it, or syncing it.
- A third origin for Repository AI; AI mutations are user-confirmed and recorded as User.

## Decisions

### Record at the process layer in `GitStatusService`
`runGitRaw`, the process branch of `runGitBounded`, `applyPatch`, and `runLFS` (recorded as `lfs <args>`, stdout only) call one `recordAudit(arguments:directory:startedAt:outcome:)` helper on the actor after the process finishes (success, `GitError.commandFailed`, or cancellation). The helper returns immediately when the command is not auditable, so read-only queries pay only a classification check.
- *Alternative:* wrap `RepositoryOperationProgress.run`/`runInBackground` call sites. Rejected: many mutations (commit, stage, checkout from sheets, AI tools) do not go through those, and the title-level wrapper cannot show the actual command.

### Classify by subcommand, skipping global options
A `nonisolated static` classifier skips leading global options (`-c key=value`, `-C path`, `--literal-pathspecs`, other `--flag`/`--flag=value`) to find the subcommand, then:
- Always auditable: `fetch pull push commit merge rebase reset revert cherry-pick add rm mv restore apply clean am clone init update-ref subtree switch checkout gc notes`.
- Conditionally: `stash` unless `list`/`show`; `branch` and `tag` when a write flag is present (`-d -D --delete -m -M -c -C -f --force -u --set-upstream-to --unset-upstream -a -s --annotate --sign` …) or a positional name is given without a listing flag (`--list -l --contains --merged --no-merged --points-at --format --show-current -a/-r` for branch); `remote` with `add remove rm rename set-url set-head set-branches prune update`; `worktree` with `add remove move prune lock unlock repair`; `submodule` except `status`/`summary`; `config` unless a read form (`--get*`, `--list`, `-l`, `get`, `list`) or a single positional key; `lfs` with `push pull fetch install uninstall track untrack migrate prune checkout`.
- Everything else is not auditable.
The same function derives the title: capitalized subcommand plus the sub-verb where relevant (`Stash push`, `Worktree add`) and the first positional argument before `--` (`Fetch origin`, `Checkout main`), with path lists after `--` summarized as a count.
- *Alternative:* record everything and filter in the UI. Rejected: status/log refreshes run every few seconds per window and would dominate storage and writes.

### Origin from a TaskLocal
`RepositoryActionAudit.origin` is a `@TaskLocal` defaulting to `.user`. `SyncState.performAutomaticFetch` runs its `GitStatusService.fetch` call inside `RepositoryActionAudit.$origin.withValue(.system)`, and so does the implicit `fetch --all` in `commitInfoIncludingRemotes` (the app fetching on its own to resolve an unknown hash). Task-locals propagate into the actor call, so the process layer reads the origin without new parameters. Any future automatic mutation marks itself the same way.

### Keep stderr on success
`GitProcessResult` gains the captured stderr. Existing callers keep using stdout `data` only; the audit output is stderr followed by stdout (trimmed), bounded to 64 KB with a truncation flag. On failure the output is the existing `GitError.commandFailed` message; cancellation records status Cancelled with no output.

### Dedicated session SQLite store
A new `actor RepositoryActionAuditStore` (`macgit/Services/RepositoryActionAuditStore.swift`) owns `Application Support/Commit+/LocalData/action-audit.sqlite` (a temporary path under XCTest, like `LocalDataStore`). It keeps one connection open for the session, and on first open deletes any existing file and creates:
`audit_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, repository_path TEXT, title TEXT, origin TEXT, command TEXT, summary TEXT, output TEXT, output_truncated INTEGER, status TEXT, finished_at REAL, duration REAL)` with an index on `(repository_path, id)`.
API: `record(_:)`, `summaries(repositoryPath:limit:)` (no `output` column), `entry(id:)`, and a synchronous `static func removeSessionFile()`. Each insert also trims the repository to the newest 1,000 rows. After a successful insert it posts `.repositoryActionAuditDidRecord` with the repository path. `repository_path` is `directory.standardizedFileURL.path`, matching the window's `repositoryURL.standardizedFileURL.path`.
- *Alternative:* a new collection in `LocalSQLiteDatabase`. Rejected: that store is the user's durable data with migrations and single-writer queuing; a throwaway, high-write log should not share its file, lock, or schema version.
- *Alternative:* in-memory ring buffer. Rejected by the requirement to keep memory flat.

Credential redaction reuses `GitCommandLogStore`'s `sanitized(arguments:)` and `shellQuoted` (made internal), plus a regex that replaces `scheme://userinfo@` in output with `scheme://<redacted>@`.

### Session lifetime
`MacgitApplicationDelegate.applicationWillTerminate` calls `RepositoryActionAuditStore.removeSessionFile()` (synchronous file removal of the database and its `-journal`). The store's first open also deletes the file, covering crashes and force quits. No launch-time work is needed beyond that lazy reset.

### Popover structure and window scoping
`RepositoryActivityHeaderButton` receives `repositoryURL` from `MainWindowView.toolbarContent`, so each window's popover reads only its own repository's records. `RepositoryBackgroundActivityPopover` gets a segmented `Picker` (Audit, Background):
- Background renders the existing content unchanged (moved into a private subview), at its current 360 pt width.
- Audit is a new `RepositoryActionAuditView` (left list ≈300 pt, right detail, ≈860×460 pt). It loads summaries (limit 1,000) on appear and on `.repositoryActionAuditDidRecord` for its repository path (received on the main actor, debounced), keeps the selected id across reloads, and loads the selected entry's output on selection. State lives in a small `@MainActor` `RepositoryActionAuditViewModel` owned by the view as `@StateObject`, released when the popover closes.
The initial tab is Background when `operationProgress.backgroundItems` is non-empty or an automatic fetch is in progress, otherwise Audit. No menu, toolbar command, or `WindowScopedNotification` is added; the audit notification is filtered by repository path, not window, because records are per repository.

## Risks / Trade-offs

- [Classifier misses a mutating form or records a read] → Unit-test the classifier against the argument shapes used in the codebase; misclassification only affects what the audit shows, never Git behavior.
- [Audit writes add latency to Git calls] → The insert is a single prepared statement on a separate actor; `recordAudit` awaits it after the process ends and swallows errors. If profiling shows contention, the call can become a detached `Task`.
- [Same repository open in two windows or via worktrees] → Records are keyed by the exact working-directory path; two windows on one repository show the same audit, which matches the spec's per-repository scope. Commands run in a subdirectory are not shown (the app runs commands at the repository root).
- [Secrets in output] → Git does not echo injected credentials; URL user info is redacted; environment is never stored. Command arguments use the existing sanitizer.
- [File removal while the actor holds a connection at termination] → Acceptable at process exit; the next launch also resets the file.

## Migration Plan

No migration. The new database file is created on first use and removed at termination. Rollback is removing the feature; a leftover file is harmless and deleted by the next build that includes the reset.
