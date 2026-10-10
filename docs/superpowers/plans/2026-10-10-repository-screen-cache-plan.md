# Repository Screen Cache — Implementation Plan

**Date:** 2026-10-10
**Status:** Not started. This document does not claim implementation or runtime verification.
**Spec:** [Repository screen cache design](../specs/2026-10-10-repository-screen-cache-design.md)
**Goal:** Show retained File status, History and Reflog data immediately on return, then reconcile stale data without losing user context.

## Working constraints

- Preserve unrelated changes and current action/undo/refresh routing. Do not commit, stash or push automatically.
- Work outside the detail-pane switch for long-lived ownership; do not keep every hidden screen mounted as a shortcut.
- Keep Git execution in existing services and UI state on the main actor. New Swift files need an AGPL notice.
- Suggested new files below are implementation targets, not existing APIs. Reuse current equivalents where appropriate.
- Build and other Xcode checks must be sequential. Honor the user's build-only/no-relaunch instruction; runtime QA remains pending. Do not run Firebase emulators.

## 1. Establish ownership and freshness primitives

**Inspect/modify:** `macgit/Views/MainWindow/MainWindowView.swift`, `macgit/App/AppState.swift`, `macgit/Services/SyncState.swift`, `macgit/Services/BoundedMemoryCache.swift`.
**Likely additions:** `macgit/ViewModels/RepositoryScreenStore.swift`, focused freshness tests under `macgitTests/`.

- [ ] Trace repository-window lifetime, including native repository tabs, and select an owner that survives sidebar navigation but is released with its repository session.
- [ ] Inventory notification producers for fetch, push, commit, branch/ref operations, stash, undo/redo, app activation and local refresh; record affected domains and existing duplicate paths.
- [ ] Add lazy ownership of screen models, active-screen tracking, repository identity, and per-domain freshness generations.
- [ ] Implement coalescing, pending invalidation during loads, current-key/result guards, cancellation cleanup and failure retry-on-next-trigger behavior.
- [ ] Move notification observation to the stable owner; retain conservative handling of existing untyped events. Ensure multiple windows receive their repository's invalidations independently.
- [ ] Cover hidden invalidation, repeated triggers, invalidation during load, error, cancellation and teardown with deterministic test cases.

**Exit:** Screen-independent freshness is defined and no invalidation is lost while a screen is hidden.

## 2. Retain History and Reflog models across navigation

**Modify:** `macgit/Views/History/HistoryScreen.swift`, `macgit/ViewModels/HistoryListModel.swift`, `macgit/ViewModels/HistoryCommitDetailModel.swift`, `macgit/Views/Reflog/ReflogView.swift`, `macgit/ViewModels/ReflogViewModel.swift`, and MainWindow wiring.

- [ ] Inject session-owned models instead of creating them in each screen. Keep action dependencies current and transient sheets scoped appropriately.
- [ ] Replace unconditional appearance reload/reset with explicit activation and ensure-loaded behavior.
- [ ] Preserve query/filter state, selected identities and loaded ranges. Keep intentional query changes distinct from background refresh.
- [ ] Preserve selection sink routing and detail suspend/resume; returning to a screen must restore commands without making hidden screens active targets.
- [ ] Reuse complete History presentation snapshots; include graph/refs revisions and all current load-key inputs.
- [ ] Enforce alternate-query cache entry and cost budgets; connect clear-session-caches behavior.
- [ ] Verify equal results do not publish new row revisions or replace equal Reflog entries.

**Exit:** Warm History/Reflog navigation uses retained data; stale activation refreshes without clearing it.

## 3. Extract File status data and refresh in the background

**Modify:** `macgit/Views/FileStatus/FileStatusView.swift`, session store and MainWindow wiring.
**Likely addition:** `macgit/ViewModels/FileStatusViewModel.swift`.

- [ ] Move status loading, snapshot data, file selection and selected-diff loading into the model, preserving existing mutation callbacks and refresh behavior.
- [ ] Display retained snapshot before activation starts a background status read.
- [ ] Publish core status independently from optional slower metadata where safe; retain generation guards for each derived result.
- [ ] Compare meaningful status, LFS, line-count and integration values before state assignment.
- [ ] Revalidate selected diff contents even when status entries remain equal; reuse the current diff revision/identity mechanisms.
- [ ] Preserve stage/unstage, conflict, commit draft and selected-file behavior; explicitly decide state ownership for each field rather than moving sheets/window controllers wholesale.
- [ ] Check unchanged status with changed contents, deleted/renamed selection, staged and unstaged versions of the same path, metadata failure and rapid selection changes.

**Exit:** File status always revalidates on return while immediately showing its most recent successful data.

## 4. Persist viewport and update the native History table selectively

**Modify:** `macgit/Views/History/HistoryCommitTable.swift`, `macgit/Views/History/HistoryCommitTableController.swift`, History row/change models, and relevant File status/Reflog list integration.

- [ ] Persist viewport anchor and offset outside native view lifetime; capture before teardown and restore after layout. Guard restoration against newer user navigation/scroll.
- [ ] Implement a pure change classifier using old/new identities, render content, refs/graph changes and pagination sentinel state.
- [ ] Skip table mutations for equal snapshots. Apply safe row insertions/removals and reload only affected row contents.
- [ ] Retain full reload fallback for complex reorderings or mismatched applied revisions, preserving selection and viewport.
- [ ] Handle anchor disappearance, row deletion, graph changes to existing rows and insertion/removal of the loading sentinel.
- [ ] Add focused cases for append, prepend, deletion, ref-only change, equal data, graph change and rebase-like reorder. Verify selection callbacks are suppressed during programmatic restoration.

**Exit:** Simple History updates avoid full reload; both incremental and fallback paths preserve valid user context.

## 5. Complete operation integration and lifecycle checks

- [ ] Verify the operation inventory from step 1 against actual code, including partial-mutation error paths and Repository AI/undo routes.
- [ ] Remove obsolete screen-level listeners or reload calls that would now duplicate session refreshes.
- [ ] Verify external changes still refresh active screens through existing local/app-active mechanisms, without adding a new polling loop or changing automatic fetch behavior.
- [ ] Check that changed load options invalidate the right query and current data cannot leak across repositories/worktrees.
- [ ] Verify hidden screens do no new Git work, pending refresh resumes on activation, and session close cancels work/releases observers.

**Exit:** All three screens use one coherent freshness mechanism and existing operations remain authoritative.

## 6. Validation and handoff

- [ ] Review focused tests for state-machine races, equality, query identity and table updates. Under the current build-only instruction, do not launch XCTest's app host; report tests not executed. If that instruction is later changed, run only relevant tests after a successful build and stop on bootstrap failure.
- [ ] Run compilation:

  ```bash
  rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] Run `rtk git diff --check` and inspect the final diff for unrelated behavior changes.
- [ ] Document implementation status and remaining interactive verification. Do not relaunch the app for this task.
- [ ] Pending runtime checklist: repeated three-screen navigation; scroll/selection restoration; action while another screen is hidden; fetch/push-only ref changes; external file edits; no-op refresh; rapid navigation during refresh; refresh error and retry; window close/reopen.
- [ ] When runtime measurement is available, compare warm-navigation time to first visible cached rows, Git request counts and History full-reload counts. Do not claim a measured latency improvement from compilation alone.

**Completion:** Code and permitted validation satisfy the spec, with unexecuted tests and runtime checks explicitly reported. Documentation-only preparation does not require a build.
