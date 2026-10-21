# Tasks

## 1. Classification and redaction

- [x] 1.1 Add `RepositoryActionAudit` (origin enum with `@TaskLocal` default `.user`, `isAuditable(arguments:)`, `title(arguments:)`) in `macgit/Services/RepositoryActionAuditStore.swift`, skipping leading global options; verify with new `RepositoryActionAuditTests` covering fetch/push/commit/apply, read-only `status`/`log`/`rev-parse`/`config --get`/`branch --show-current`/`stash list`/`tag -l`, write forms of `branch`/`tag`/`remote`/`worktree`/`config`, `-c`-prefixed commands, and titles such as `Fetch origin` and `Stash push`
- [x] 1.2 Make `GitCommandLogStore.sanitized(arguments:)` and `shellQuoted` internal and add output URL-userinfo redaction; verify in `RepositoryActionAuditTests` that `https://user:secret@host/repo.git` and `--token x` are redacted in commands and output

## 2. Session store

- [x] 2.1 Implement `actor RepositoryActionAuditStore` (session SQLite file under `Application Support/Commit+/LocalData/action-audit.sqlite`, temp path under XCTest; reset on first open; `record`, `summaries(repositoryPath:limit:)` without output, `entry(id:)`, 64 KB output cap with truncation flag, 1,000-row per-repository trim, `.repositoryActionAuditDidRecord` notification, synchronous `removeSessionFile()`); verify with `RepositoryActionAuditStoreTests` using a temporary database URL: insert/read order newest first, summaries exclude output, truncation flag, row trim, reset on reopen, and per-repository filtering
- [x] 2.2 Call `RepositoryActionAuditStore.removeSessionFile()` from `MacgitApplicationDelegate.applicationWillTerminate`; verify by build and by checking the file is gone after quitting the app

## 3. Capture in GitStatusService

- [x] 3.1 Keep stderr in `GitProcessResult` on success and add the private `recordAudit` helper on `GitStatusService`, called from `runGitRaw`, the process branch of `runGitBounded`, and `applyPatch` for success, failure, and cancellation; verify with `RepositoryActionAuditIntegrationTests` (temporary repository with a local bare remote): a push and a commit produce records with command, status, and stderr output; `git status`/`log` produce none; a failing command records its error; existing callers still receive stdout only
- [x] 3.2 Wrap the `GitStatusService.fetch` call in `SyncState.performAutomaticFetch` with `RepositoryActionAudit.$origin.withValue(.system)`; verify in `RepositoryActionAuditIntegrationTests` that a fetch under the system origin is stored as System and a plain fetch as User
- [x] 3.3 Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/RepositoryActionAuditTests -only-testing:macgitTests/RepositoryActionAuditStoreTests -only-testing:macgitTests/RepositoryActionAuditIntegrationTests -only-testing:macgitTests/RepositoryOperationProgressTests -only-testing:macgitTests/SyncStateBackgroundRemoteIntegrationTests test` and confirm all pass

## 4. Popover UI

- [x] 4.1 Pass `repositoryURL` from `MainWindowView.toolbarContent` into `RepositoryActivityHeaderButton` and on to the popover; verify by build
- [x] 4.2 Split `RepositoryBackgroundActivityPopover` into a tabbed container (segmented Audit/Background picker, initial tab Background when background items exist or an automatic fetch runs, else Audit) with the existing background content moved unchanged into the Background tab; verify the Background tab still shows the automatic-fetch row, running/queued/failed items, View, and dismiss
- [x] 4.3 Add `RepositoryActionAuditViewModel` and `RepositoryActionAuditView` (left list newest first with title, summary, time, failure marker, User/System pill; right pane with title, status, date/time, selectable `$ git …` command and output, truncation note; empty state; reload on `.repositoryActionAuditDidRecord` for the repository path while keeping selection; output loaded on selection); verify by build
- [ ] 4.4 Launch the app and review the popover in a repository window: switch tabs, trigger a manual fetch and wait for an automatic fetch, confirm User/System pills, selection persistence while new items arrive, detail layout at a narrow and a wide window, dark mode, and that a second repository window shows only its own records; note any interaction not checked

## 5. Integration checks

- [ ] 5.1 Quit and relaunch the app, confirm the Audit tab starts empty and the session database file was removed at quit
- [x] 5.2 Run `git diff --check` and confirm no whitespace errors

## Workflow follow-up

- Archive the change with `/opsx:archive` after implementation and review.
