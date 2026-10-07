# History Screen Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the History screen to replace `HistoryView` (2681 lines, SwiftUI `Table` plus many workarounds) while keeping the UI and the click, double-click, right-click and drag behavior on commit rows.

**Spec:** `docs/superpowers/specs/2026-10-07-history-screen-rewrite-design.md`. Every task is written against **§4 Behavior contract** in the spec. Use the old code for lookup only; do not copy its structure.

**Architecture:** A thin SwiftUI `HistoryScreen` composes `BranchFilterBar`, `HistoryCommitTable` (an `NSViewRepresentable` wrapping `NSTableView`) and `HistoryCommitDetailView`. State lives in three `@Observable @MainActor` models: `HistoryListModel`, `HistoryCommitDetailModel` and `HistoryCommitActionController`.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSTableView`), Observation, `GitStatusService`.

**Plan scope:** code changes only. No performance measurement steps and no new tests. Existing tests are only retargeted or deleted as described in spec §7.

**Conventions:**
- Branch: `codex/history-rewrite`.
- New Swift files start with `// SPDX-License-Identifier: AGPL-3.0-or-later`.
- The project uses synchronized folders, so adding or deleting files needs no `macgit.xcodeproj` edits.
- New code lives alongside the old code; MainWindow keeps using `HistoryView` until Task 8.
- Do not modify `GitStatusService`, `CommitGraphGenerator`, `HistoryCommitSelection` or the subviews listed in spec §3.
- End of every task: `rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` must succeed.

---

### Task 1: Shared foundation

**Files:**
- Create: `macgit/Views/History/HistoryLoadPolicy.swift`
- Create: `macgit/Views/History/CommitGraphRowRenderer.swift`
- Modify: `macgit/Views/History/RefLabel.swift`

- [ ] **Step 1: `HistoryLoadPolicy`** — `enum HistoryLoadPolicy` with `Scope` (`allBranches` / `currentBranch` / `ref(String)`) and the pure functions in spec §4.8, using exactly those names and semantics. Add `loadKey(filter:searchQuery:pageSize:onlyThisBranch:baseBranch:)` and `emptyDetail(onlyThisBranch:filter:baseBranch:searchQuery:)`. Do not add the functions removed in spec §5.
- [ ] **Step 2: `RefLabelStyle`** — in `RefLabel.swift`, add `struct RefLabelStyle { init(text: String, graphColorIndex: Int?) }` exposing `displayText`, `isTag`, `symbolName`, `foreground: NSColor`, `background: NSColor` (tag: purple, 15% background; graph color: `GraphPalette`, 20% background; otherwise accent, 15% background). Make `RefLabel` use it with no visual change. Add an `NSColor` accessor to `GraphPalette` if missing.
- [ ] **Step 3: `CommitGraphRowRenderer`** — `enum CommitGraphRowRenderer` with constants `rowHeight = 24`, `laneWidth = 14`, `dotSize = 8` and
  ```swift
  static func draw(_ geometry: CommitGraphRowGeometry, rowIndex: Int,
                   in context: CGContext, dotBackground: NSColor)
  ```
  Draw per spec §4.1 / §6.6: stroke `path.cgPath` with 2.2 line width and round caps/joins, colors from `BranchGraphCanvas.lineColor(colorIndex:isHighlighted:)` (add an `NSColor` variant if needed), translated by `rowIndex * rowHeight` because geometry uses global coordinates; draw dots as `BranchGraphCanvas.drawDot` does.
- [ ] **Step 4:** Build.

### Task 2: `HistoryListModel`

**Files:**
- Create: `macgit/ViewModels/HistoryListModel.swift`
- Modify: `macgit/Views/History/HistoryPagingState.swift`

- [ ] **Step 1: One-directional paging** — reduce `HistoryPagingState` to `pageSize`, `loadedCount`, `hasMore`, `isLoadingMore`, `reset()`, `beginLoadingMore()`, `finishLoadingMore(loaded:)`, `replaceLoadedHistory(count:hasMore:)`, `cancelLoadingMore()`. Remove `startIndex`, `canLoadNewer`, `beginLoadingNewer` and `replaceWindow` (spec §5). The old `HistoryView` calls the removed members: temporarily switch it to `replaceLoadedHistory` and drop its `loadNewer` branch so it still builds (the file is deleted in Task 9).
- [ ] **Step 2: Types** — `HistoryRows`, `HistoryScrollRequest` and `HistoryListModel.Phase` per spec §6.2.
- [ ] **Step 3: Loading** per spec §4.2:
  - `load()`: use the cache when the key is cached; otherwise query the first page by scope / search / only-this-branch, resolve the HEAD hash and highlight root, build the graph (`generateIncrementalAsync`) and publish `.reload(preserveViewport: false)`. Discard the result if `loadKey` changed or the task was cancelled.
  - `refresh()`: reload `max(pageSize, commits.count)` commits from `skip = 0` and publish `.reload(preserveViewport: true)`.
  - `loadMoreIfNeeded(lastVisibleRow:visibleCount:)`: use the §4.2 threshold, load the next page, extend the graph with `appendAsync` from the retained `CommitGraphGenerationState` and publish `.appended(oldCount..<newCount)`.
  - A single `publish(commits:graphResult:hasMore:change:)` assigns `rows` (version + 1, builds `indexByHash`), updates `headHash` and stores the cache entry.
  - `phase`: `.initialLoading` while there are no commits; `.refreshing` only when a load with existing commits takes longer than 150 ms.
- [ ] **Step 4: Search** — `setSearchText(_:)` per spec §4.2 (fewer than 3 characters applies an empty query immediately; otherwise debounce 800 ms). `activeSearchQuery` is `private(set)` and part of `loadKey`.
- [ ] **Step 5: Selection** per spec §4.3:
  - Default selection after `load()` (the `selectedBranch` tip for `.all` with no search, otherwise the first commit), always reselected on a key change, plus a `scrollRequest`.
  - Selection from cache (tip first, then the stored commit, then the first commit).
  - After `refresh()`: keep the selection and drop missing hashes; if the primary is gone, keep the previous `selectedCommit` (pinned).
  - `applyTableSelection(orderedHashes:)`: empty → clear selection and `selectedCommit`; otherwise derive the primary with `HistoryLoadPolicy.primaryHashForTableSelection` and update `selection` and `selectedCommit`. No-op when the hash set is unchanged.
  - `selectBranchTipIfPossible()`: emits a `scrollRequest` with `focus: true`.
  - `selectedHashesInDisplayOrder` sorts by `indexByHash`.
- [ ] **Step 6: Helpers** — `clearCache()`, `setPageSize(_:)` (clears the cache), `setDragActive(_:)`, `consumeScrollRequest(_:)`. Mark every piece of state the views do not read as `@ObservationIgnored`.
- [ ] **Step 7:** Build.

### Task 3: Detail model and detail view

**Files:**
- Create: `macgit/ViewModels/HistoryCommitDetailModel.swift`
- Create: `macgit/Views/History/HistoryCommitDetailView.swift`

- [ ] **Step 1: Model** per spec §6.3 and §4.4:
  - `show(_:)`: same hash → no-op. Different → assign `commit`, close the popover, clear the full message, clear the data and "done" flags of all three parts, cancel tasks, wait 80 ms, then load.
  - Loading: line counts run concurrently with the file list; when the file list finishes, assign `fileChanges` and select a file (keep the previous one if present, otherwise the first); assign line counts when they finish; then load patch eligibility. Each part has a "done" flag tied to the commit hash, and every result checks the current commit hash before assignment.
  - `selectedFile` `didSet` loads the diff and stores it with the commit hash and path.
  - `suspend()` cancels tasks; `resume()` loads only unfinished parts for the current commit without clearing results or the selected file.
  - `loadFullMessage()` uses `GitStatusService.fullCommitMessage` and discards the result if the commit changed.
  - `patchDisabledReason(for:)` follows the priority order in spec §4.4.
- [ ] **Step 2: View** — `HistoryCommitDetailView(model:repositoryURL:undoManager:syncState:runOperation:)` builds the detail layout from spec §4.1: header, popover, patch-preparation row, and a `PersistentHSplit` with `CommitFileListView` (preview → `model.fullFilePreview`, file patch → `model.patchController.prepare(...)`) and the diff viewer (`DiffView`; line patches only when the diff matches the commit and file).
- [ ] **Step 3: Detail-owned sheets** — `CommitFilePreviewSheet` (available size measured with `onGeometryChange` in this view), `CommitPatchReviewSheet` (reads the current `model.patchController.prepared` on every render; dismissing calls `closeConflict()`), and the "Selected changes" alert.
- [ ] **Step 4:** Build.

### Task 4: Action controller and sheets

**Files:**
- Create: `macgit/ViewModels/HistoryCommitActionController.swift`
- Create: `macgit/Views/History/HistoryActionSheets.swift`

- [ ] **Step 1: Controller** per spec §6.4 (`Presentation`, `revertCandidate`, `errorMessage`, `@ObservationIgnored` `Dependencies`).
- [ ] **Step 2: Opening sheets and alerts** — request functions matching the "Action" column of the context menu table in spec §4.5; `requestReset` fetches `currentBranch` before setting `presentation`; `handleDoubleClick(_:)` per spec §4.5 (discard the `uncommittedChangeCount` result if another commit was requested meanwhile).
- [ ] **Step 3: Execution** — implement the execution functions exactly as in the spec §4.7 table: `GitStatusService` calls, undo registration, the dedicated cherry-pick / revert error messages, posting `.repositoryDidChange`, dismissing the presentation. Share `registerHeadUndo(label:oldHead:redo:)`. Wrap each operation in `dependencies.runOperation(<message from spec §4.6>)`.
- [ ] **Step 4: Cross-check** — compare every row of the §4.7 table with `HistoryView.swift:1952-2322` (call, arguments, undo label, mode, expectedHead, redo). This step is mandatory before moving on.
- [ ] **Step 5: Sheets** — `HistoryActionSheets.swift`: six views (`HistoryTagSheet`, `HistoryBranchSheet`, `HistoryResetSheet`, `HistoryMergeSheet`, `HistoryRebaseSheet`, `HistoryCheckoutSheet`), each holding its inputs in `@State` and calling the controller's execution function; text, sizes and shortcuts per spec §4.6. A `historyActionPresentations(_:)` modifier with one `.replacingSheet(item:)` switching on `Presentation` (squash → `SquashCommitsSheet`), the "Reverse this commit?" alert and the "Error" alert.
- [ ] **Step 6:** Build.

### Task 5: Context menu

**Files:**
- Create: `macgit/Views/History/HistoryCommitContextMenu.swift`

- [ ] **Step 1:** `struct HistoryCommitContextMenu: View` taking `contextCommits` (display order), `primaryCommit`, `headHash`, `repositoryURL` and `controller`. Build exactly the table in spec §4.5 (order, dividers, icons, `.disabled` conditions, singular / plural titles). Custom Actions uses `CustomActionMenuContent(store:surface: .selectedCommits, context:onRun:)` with the store from `@EnvironmentObject`; `onRun` → `controller.dependencies.runCustomAction(id, hashes)`.
- [ ] **Step 2:** Build.

### Task 6: AppKit table

**Files:**
- Create: `macgit/Views/History/HistoryCommitTable.swift`
- Create: `macgit/Views/History/HistoryCommitTableController.swift`
- Create: `macgit/Views/History/HistoryCommitTableCells.swift`
- Create: `macgit/Views/History/HistoryRefBadgeView.swift`

- [ ] **Step 1: Representable and `HistoryNSTableView`** — `HistoryCommitTable(listModel:actions:customActionStore:repositoryURL:textScale:)`; `makeCoordinator` creates the controller; `makeNSView` builds the `NSScrollView` + `HistoryNSTableView` per spec §6.5 "Built once" (including initial widths from `history.tableColumnRatios` when the `NSTableView Columns HistoryCommitTable` autosave is missing); `dismantleNSView` removes observers.
- [ ] **Step 2: Data source** — row count = commits + 1 when `hasMore`; `viewFor` by column identifier; the loading row has a cell only in the `message` column.
- [ ] **Step 3: `apply(...)`** — the six update rules in spec §6.5, tracking `appliedVersion`, `appliedTextScale`, `appliedDragActive` and `lastScrollToken`. `updateNSView` reads only the four model properties and calls `apply`.
- [ ] **Step 4: Viewport-driven paging** — observe the clip view's `boundsDidChangeNotification` → `loadMoreIfNeeded`; also call it after each `rows` change.
- [ ] **Step 5: Selection** — `tableViewSelectionDidChange` and `selectionIndexesForProposedSelection` per spec §6.5.
- [ ] **Step 6: Context menu** — `menuNeedsUpdate` per spec §6.5: build `NSHostingMenu(rootView: HistoryCommitContextMenu(...).environmentObject(customActionStore))` and move its items into `tableView.menu`.
- [ ] **Step 7: Double-click / Return** — `doubleAction` and `keyDown` → `actions.handleDoubleClick`.
- [ ] **Step 8: Cells** per spec §4.1 and §6.5:
  - `HistoryGraphCellView`: geometry from `graphModel.rowGeometryCache.geometry(for:rowIndex:)`, drawn with `CommitGraphRowRenderer`; dot background = `selectedContentBackgroundColor` when `backgroundStyle == .emphasized`, otherwise `alternatingContentBackgroundColors[row % n]`; draw across the full row height so lines join between rows.
  - `HistoryMessageCellView`, `HistoryTextCellView`, `HistoryLoadingCellView`.
  - Fonts from `NSFont.preferredFont(forTextStyle: .callout)` scaled by `textScale`; colors `secondaryLabelColor` / `tertiaryLabelColor`.
- [ ] **Step 9: `HistoryRefBadgeView`** — a capsule with a 10 pt semibold SF Symbol and 11 pt semibold × textScale text, styled by `RefLabelStyle`; `intrinsicContentSize` from content; emphasized state per spec §4.1.
- [ ] **Step 10:** Build.

### Task 7: Drag

**Files:**
- Modify: `macgit/Views/History/HistoryCommitTableController.swift`

- [ ] **Step 1:** `pasteboardWriterForRow` — only for `dragOriginRow` (and not the loading row): compute the dragged commits per spec §4.5 with `HistoryLoadPolicy.draggedCommits`, build the payload, call `GitDragPayloadStore.set`, and return an `NSPasteboardItem` with `GitDragPayload.encodeTransferData(payload)` for type `UTType.macgitGitDragPayload.identifier`. Other rows return `nil`.
- [ ] **Step 2:** `draggingSession(_:willBeginAt:forRowIndexes:)` — render `CommitDragPreview` with `ImageRenderer` (color scheme from `effectiveAppearance`, scale from `backingScaleFactor`), set it as the dragging frame centered on the cursor, set `draggingFormation = .none`, and call `listModel.setDragActive(...)`.
- [ ] **Step 3:** `draggingSession(_:endedAt:operation:)` — `listModel.setDragActive([])`; do not clear `GitDragPayloadStore`.
- [ ] **Step 4:** Review every commit drop target (`SidebarView+DragDrop.swift` and anything calling `GitDragPayloadStore.currentPayload()` or `dropDestination(for: GitDragPayload.self)`) to confirm it works with a single dragging item. Record the conclusion in the PR description.
- [ ] **Step 5:** Build.

### Task 8: `HistoryScreen` and MainWindow

**Files:**
- Create: `macgit/ViewModels/HistoryCommitSelectionSink.swift`
- Create: `macgit/Views/History/HistoryScreen.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Sink**
  ```swift
  @Observable @MainActor
  final class HistoryCommitSelectionSink {
      private(set) var commitHashes: [String] = []
      func update(_ hashes: [String]) {
          guard hashes != commitHashes else { return }
          commitHashes = hashes
      }
  }
  ```
- [ ] **Step 2: `HistoryScreen`** per spec §6.7 and the §4.1 layout: `init` creates the three models (page size read from `advanced.historyLoadSize`); the body is `BranchFilterBar` + loading / empty / a `ZStack` with the `PersistentVSplit` (table | detail) and the refresh capsule; keep `.id("history")`, the frame and the `windowBackgroundColor` background.
- [ ] **Step 3: Wiring** —
  - `.onChange` of `branchFilter`, `onlyThisBranch`, `baseBranch`, `selectedBranch`, `historyLoadSizeRaw` → assign to `listModel`; a `selectedBranch` change also calls `selectBranchTipIfPossible()`; `searchText` → `setSearchText`.
  - `.task(id: listModel.loadKey) { await listModel.load() }`.
  - `.onReceive` `.repositoryDidChange` and `.repositoryLocalStateDidRefresh` (filtered by `repositoryURL`) → `clearCache()` + `refresh()`; `.advancedClearSessionCaches` → the same.
  - `.onChange(of: listModel.selectedCommit?.hash)` → `detailModel.show(listModel.selectedCommit)`.
  - `.onChange(of: listModel.selectedHashesInDisplayOrder)` → `selectionSink.update(...)`.
  - `.onAppear` / `.onDisappear` per spec §6.7; assign `actions.dependencies` in the body; `.historyActionPresentations(actions)`; error alert for `listModel.errorMessage`.
- [ ] **Step 4: MainWindow** —
  - Add `@State private var historySelectionSink = HistoryCommitSelectionSink()`; remove `customActionCommitHashes` (`MainWindowView.swift:204`) and move every read / write to the sink (`:825-829` and any reset sites).
  - Replace the `HistoryView(...)` block (`:1376-1397`) with `HistoryScreen(...)`, passing `$appState.historyBranchFilter`, `$appState.historyIncludeRemotes`, and `Dependencies` built from the existing closures (`runRepositoryOperation`, `checkoutRequest`, `explainCommitWithRepositoryAI`, browse revision, `runCustomAction(... surface: .selectedCommits)`), with `headHash` read from `listModel` through a closure.
- [ ] **Step 5:** Build.

### Task 9: Remove old code

**Files:**
- Delete: `macgit/Views/History/HistoryView.swift`, `HistoryTableScrollCoordinator.swift`, `HistoryDragPreviewDataSource.swift`, `HistoryCommitMessageCell.swift`, `HistoryTableRow.swift`
- Delete (if unused): `macgit/Views/History/BranchGraphRowCanvas.swift`
- Modify: `macgitTests/HistoryViewTests.swift`, `macgitTests/HistoryPaginationTests.swift`
- Delete: `macgitTests/HistoryTableScrollCoordinatorTests.swift`

- [ ] **Step 1:** Grep for `HistoryView`, `HistoryTableScrollCoordinator`, `HistoryTableIntrospectionView`, `HistoryTableRow`, `HistoryCommitMessageCell`, `BranchGraphRowCanvas` and `HistoryDragPreviewDataSource`; delete the files above once nothing in the app references them.
- [ ] **Step 2: Tests (compile only)** —
  - `HistoryViewTests`: change `HistoryView.` to `HistoryLoadPolicy.` for the functions in spec §4.8; delete the tests for `selectCommitFromNativeTap` and `contextMenuCommits`.
  - `HistoryPaginationTests`: delete tests that use `replaceWindow` / `canLoadNewer`.
  - Delete `HistoryTableScrollCoordinatorTests.swift`.
- [ ] **Step 3:** Grep for `history.tableColumns` and `history.tableColumnLayout` and remove code that still reads or writes those keys (do not delete users' stored values).
- [ ] **Step 4:** Build. `rtk git diff --check`.

---

## Order and dependencies

```
Task 1 ──┬─> Task 2 ──────────────┐
         ├─> Task 4 ─> Task 5 ────┴─> Task 6 ─> Task 7 ──┐
         └─> Task 3 ─────────────────────────────────────┴─> Task 8 ─> Task 9
```

Tasks 2, 3 and 4 are independent after Task 1. The table (Task 6) needs the list model (2), the action controller (4) and the context menu (5). The detail work (3) only has to land before the screen is assembled in Task 8. The new screen appears in the app from Task 8 onward.

## Behavior checklist (run the app after Task 8, against spec §4)

- [ ] Layout: 5 columns, continuous graph, ref badges + "+N", selection colors, loading row, refresh capsule, empty states, detail header / popover / file list / diff.
- [ ] Click, Shift-click, Cmd-click, ↑↓, Shift+↑↓; holding ↑↓ loads detail only for the final commit.
- [ ] Right-click an unselected row → selects only it; right-click a selected row → keeps selection and detail.
- [ ] Every context menu item: order, enablement, Custom Actions, Copy.
- [ ] Double-click / Return: checks out the branch ref, or opens the detached sheet (with and without uncommitted changes).
- [ ] Each operation in spec §4.7 works, Undo / Redo behave correctly, and cherry-pick / revert conflicts show the right message.
- [ ] Drag one / several commits onto the sidebar; one preview image with a badge; dragged rows dimmed.
- [ ] Scrolling down loads more pages; refresh after fetch / commit keeps selection and scroll position; a selected commit that disappears after a reset keeps its detail.
- [ ] Branch filter, include remotes, only-this-branch + base, search (< 3 characters, debounce), history load size change, returning to a previous filter served from cache.
- [ ] Picking a branch in the sidebar with filter `.all` → selects its tip, scrolls to it, focuses the table.
- [ ] Reflog "Show Commit" opens History at the right commit.
- [ ] Hide / show Author, Date, Commit; resize columns; layout persists across launches; first launch uses the legacy ratios.
- [ ] Toolbar Custom Actions receives the selected commits.
- [ ] Leaving the screen while detail is loading and coming back resumes loading without losing the selected file.
