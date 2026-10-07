# History Screen Rewrite — Design Spec

**Date:** 2026-10-07
**Scope:** Rewrite the History screen, replacing `macgit/Views/History/HistoryView.swift` and the SwiftUI `Table` workarounds around it.
**Approach:** Write new code from the behavior contract (§4). Do not port the old code; use it only as a reference for behavior.
**Implementation plan:** `docs/superpowers/plans/2026-10-07-history-screen-rewrite-plan.md`

---

## 1. Background

History and Reflog both use a SwiftUI `Table` with a detail panel, yet History is noticeably slower when clicking a commit, navigating with the keyboard, and scrolling. The cause is architectural:

| Problem | Current location |
|---|---|
| ~60 `@State` properties in one 2681-line struct. Any detail change (`fileChanges`, `commitLineCounts`, `diffHunks`, `selectedFile`, `showingCommitInfo`, …) re-evaluates the whole body, including the `Table` rows builder | `HistoryView.swift:47-122` |
| `@EnvironmentObject AppState` (29 `@Published` properties): any unrelated AppState change invalidates History | `HistoryView.swift:42` |
| Every selection change calls `onCustomActionSelectionChanged`, which writes `MainWindowView` `@State`. MainWindow re-renders, `HistoryView` is rebuilt with new closures, and its body runs again | `HistoryView.swift:706-709`, `MainWindowView.swift:1385` |
| Several O(n) passes per click: `Set(commits.map(\.hash))` in the binding setter, `applyTableSelection`, the context menu builder | `HistoryView.swift:1853-1925`, `1052` |
| Heavy cells: a `GeometryReader` plus an introspection `NSViewRepresentable` in every message cell, a `Canvas` per row, three `.help()` per row, per-cell `onAppear` driving pagination | `HistoryCommitMessageCell.swift`, `HistoryView.swift:725-816`, `1937` |
| Every cell reads `activeDragCommitHashes`, so starting a drag updates every cell | `HistoryView.swift:733,746` |
| SwiftUI `Table` workarounds: an `NSEvent` monitor for right-click, swapping the table `dataSource` to replace the drag preview, manual column width restoration, click suppression after drag, 50 ms mouse polling | `HistoryTableScrollCoordinator.swift`, `HistoryDragPreviewDataSource.swift`, `HistoryView.swift:2572-2648` |

## 2. Goals

1. Clicking or arrowing to a commit does **not** re-evaluate table rows; only the detail panel updates.
2. Scrolling runs no per-cell SwiftUI code; pagination is driven by the viewport.
3. External changes (AppState, MainWindow re-renders, new closures) never reload the table.
4. Use `NSTableView` directly, with no workarounds.
5. Keep the new code lean: do not carry over dead code or state flags that only exist to patch the old foundation (§5).

## 3. Layers: what to rewrite, what to keep

| Layer | Treatment | Components |
|---|---|---|
| History UI and state | **Rewrite completely** from §4 | list model, detail model, action controller, AppKit table, cells, context menu, drag, `HistoryScreen`, History sheets |
| Git operations and undo | **Rewrite the structure, keep the git contract** in §4.7: the same `GitStatusService` calls, the same `GitUndoEntry` values, the same error messages, the same notifications | action execution functions |
| Small pure logic with existing tests | Rewrite in `HistoryLoadPolicy`, **keeping names and semantics** so existing tests only need a prefix change | §4.8 |
| Infrastructure | **Do not touch** | `GitStatusService`, `CommitGraphGenerator` (+ `CommitGraphRowGeometryCache`, `CommitGraphModel`), `HistoryCommitSelection`, `HistoryCheckoutPolicy`, `BoundedMemoryCache`, `CommitPatchController`, `GitDragPayload` / `GitDragPayloadStore`, `CustomActionStore` / `CustomActionMenuContent`, `GitUndoManager` |
| Shared subviews | **Do not touch** | `BranchFilterBar`, `CommitFileListView`, `DiffView`, `CommitInfoPopoverView`, `CommitFilePreviewSheet`, `CommitPatchReviewSheet`, `SquashCommitsSheet`, `CommitDragPreview`, `RefLabel` (style extraction only, §6.6), `EmptyStateView`, `PersistentVSplit` / `PersistentHSplit` |

## 4. Behavior contract

This is the source of truth for the new code. References to old line numbers are for lookup only, not for porting.

### 4.1 Layout

- Top to bottom: `BranchFilterBar`, then content.
- Content:
  - Initial load with no commits yet: `ProgressView("Loading history…")` centered.
  - No commits: `EmptyStateView` with icon `clock.arrow.circlepath`, message "No commits to display" (or "No matching commits" while searching), and detail from `emptyDetail` (§4.8).
  - Commits available: a vertical `PersistentVSplit` with autosave name `HistoryMainSplit` (min top 200, min bottom 180), table on top and detail below.
  - Refreshing with existing data for longer than 150 ms: a `.regularMaterial` capsule at the top edge with a spinner and "Loading branch history…" (caption, secondary).
- Table:
  - Five columns: Graph (min 60, width 200), Message (min 120, width 400), Author (min 140, width 180), Date (min 100, width 140), Commit (min 72, width 80). Graph and Message cannot be hidden or reordered; Author, Date and Commit can be hidden. Column layout persists.
  - Bordered style (vertical grid lines), alternating rows, small control size, 24 pt row height.
  - Graph: lanes and dots from `CommitGraphRowGeometry`, 2.2 pt lines with round caps and joins, continuous across rows. Dot background matches the row background (alternating), or the selection color when the row is selected and the table has focus.
  - Message: up to 3 ref badges (`RefLabel` appearance, tinted with the commit's graph color), then "+N" (caption, secondary, tooltip listing the remaining refs), then the message on one line, tail-truncated, with the message as tooltip. An empty message shows "<empty message>". On a selected row, badges switch to primary text on a 12% primary background.
  - Author: "name <email>", callout, secondary, same string as tooltip.
  - Date: hour, minute, day, abbreviated month, year; callout, secondary, monospaced digits.
  - Commit: short hash, monospaced callout, tertiary, full hash as tooltip.
  - Fonts scale with `appTextScale`.
  - While older pages remain: the last row shows a small spinner and "Loading older commits…".
- Detail (same appearance as `HistoryView.swift:820-1019`):
  - No commit selected: `EmptyStateView` "Select a commit".
  - Header: person icon, message (semibold 13, one line), a secondary line with author • email • date and time • full hash; an info button opening `CommitInfoPopoverView` (loads the full message on open; copy message / copy hash); up to 5 `RefLabel`s. `.ultraThinMaterial` background with a bottom hairline.
  - While a patch is being prepared: a row with a spinner, "Checking and merging selected changes…" and a Cancel button.
  - A horizontal `PersistentHSplit` with autosave name `HistoryDetailSplit` (min left 220, min right 300): `CommitFileListView` | diff viewer (file name header plus `DiffView` with `gitRef` set to the commit, line-level patch support). No file selected: `EmptyStateView` "Select a file".

### 4.2 Loading

- **Scope** from `HistoryBranchFilter`: `.all` → all branches; `.current` → HEAD; `.branch(ref)` → that ref.
- **Queries** (`GitStatusService`):
  - "Only this branch" on and filter not `.all`: requires a base branch; with no base selected the list is empty. With a base: `branchOnlyCommitHistory(branch:base:query:limit:skip:)`, where branch is the ref, or `"HEAD"` for `.current`.
  - No search: `commitHistory(allBranches:…)` or `commitHistory(branch:…)`.
  - Search: `searchCommitHistory(allBranches:…)` or `searchCommitHistory(branch:…)`.
- **Search:** a trimmed query shorter than 3 characters counts as no search and applies immediately. Three characters or more apply 800 ms after the last keystroke.
- **One-directional pagination:** the first page uses `skip = 0`, `limit = pageSize`. Each next page uses `skip = number of loaded commits`. Pagination ends when a page returns fewer than `limit` commits. Load the next page when the last visible row is within `max(pageSize, visible row count × 3)` of the end. Never load two pages concurrently.
- **Page size:** the `advanced.historyLoadSize` setting (`HistoryLoadSize`, default `.balanced`). Changing it clears the cache and reloads.
- **Load key** = filter + applied search + page size + (only-this-branch ? base : "full"). A new key reloads from the start and cancels the previous load. Results for an outdated key are discarded.
- **Graph:** `CommitGraphGenerator.generateIncrementalAsync` for a fresh load, `appendAsync` for an added page. Highlighting is `.all` for the `.all` filter, otherwise `.currentBranchOnly`. Highlight root from `highlightRootHash` (§4.8). HEAD hash comes from a commit's ref decoration (`HEAD` / `HEAD -> …`), falling back to `tipHash(for: "HEAD")`.
- **Cache:** up to 3 snapshots keyed by load key (commits, selected commit, hasMore). Returning to a cached key shows it immediately (graph recomputed) without running git log. The cache is cleared when the repository changes or on `.advancedClearSessionCaches`.
- **Refresh:** on `.repositoryDidChange` or `.repositoryLocalStateDidRefresh` for the matching `repositoryURL`, or on `.advancedClearSessionCaches`, clear the cache and reload **as many commits as are currently loaded** (at least one page), preserving selection and scroll position.

### 4.3 Selection

- Selection consists of the selected hash set, the primary hash (shown in detail) and the anchor, stored as `HistoryCommitSelection`.
- Click, Shift-click, Cmd-click, ↑↓ and Shift+↑↓ follow standard `NSTableView` behavior. The primary hash is derived with `primaryHashForTableSelection` (§4.8).
- **After a fresh load** (key change, not refresh):
  - Filter `.all`, no search, and the tip of `selectedBranch` is in the page → select that tip.
  - Otherwise → select the first commit.
  - Always reselect, even if the previously selected commit is still present in the new list (`HistoryView.swift:1396`).
  - Scroll to the selected commit.
- **From cache:** filter `.all` and the tip of `selectedBranch` is in the snapshot → select it; otherwise select the snapshot's stored commit; otherwise the first commit.
- **After refresh:** keep the selection. Hashes no longer present drop out of the table selection. If the primary commit disappeared, keep showing its detail (do not blank the panel) until the user selects another commit (`HistoryView.swift:1898-1903`).
- **Adding a page:** selection and scroll position stay unchanged.
- **`selectedBranch` changes** (branch picked in the sidebar) while the filter is `.all` and there is no search → select that branch's tip if loaded, scroll to it and focus the table.
- An empty table selection (user deselects everything) → detail shows "Select a commit".
- The selection, in display order, is published to the toolbar Custom Actions (§6.8).

### 4.4 Detail

- When the primary commit changes, the header updates immediately; the file list loads after the selection has been stable for 80 ms (holding ↑↓ only loads the final commit).
- Three parts load; late results for a previous commit are discarded:
  - File list: `changedFiles(in:in:)`. When done, keep the selected file if still present, otherwise select the first file.
  - Line counts: `commitLineChangeCounts(in:in:)`, concurrently with the file list; errors are ignored.
  - Patch eligibility: `commitPatchUnavailableReasons(commit:in:)`; on error, store the error message.
- Changing the file loads its diff (`HistoryView.swift:1821-1851`). Line patches are allowed only when the shown diff matches the selected commit and file; otherwise the reason is "Loading commit diff…".
- Patch-disabled reason, in priority order: merge commit → "Selected changes from merge commits are not supported."; preparing or applying → "Preparing or applying selected changes…"; eligibility not checked yet → "Checking selected changes…"; eligibility error → the error message; then the per-file reason (by path or oldPath).
- If the screen disappears mid-load, cancel. On return with the same commit, **resume unfinished parts without clearing finished results or the selected file**. Empty results are valid, so completion must be tracked with a separate flag per part rather than inferred from the data (`HistoryView.swift:1771-1772`).
- Changing the commit closes the commit info popover and clears the loaded full message.
- The patch review sheet must read the latest review state after each resolution, not the snapshot from when the sheet opened (`HistoryView.swift:336`). Closing the sheet closes the conflict window.

### 4.5 Row interactions

- **Double-click or Return** on a commit (Return uses the selection's primary commit):
  - Commit has a branch ref (`HistoryCheckoutPolicy.branchRef(from:)`) → `requestCheckout(branchRef, false)`.
  - Otherwise → check `uncommittedChangeCount` and open the detached checkout sheet (with a "Discard local changes" checkbox when there are uncommitted changes). If the user has requested a different commit by the time the count returns, discard the result.
  - A double-click must not fire right after a drop.
- **Right-click:**
  - On an unselected row → select only that row, then open the menu for it.
  - On a selected row → **keep** the selection and detail; the menu applies to the whole selection (`HistoryView.swift:1859-1861`).
  - On the loading row or empty space → no menu.
  - Build the menu from the clicked row; do not depend on `NSApp.currentEvent` (`HistoryView.swift:689-691`).
- **Context menu** (order, icons, enablement; "single" = exactly one commit in context; "primary" = the detail commit if it is in context, otherwise the first context commit):

  | Item | Icon | Enabled when | Action |
  |---|---|---|---|
  | Show Repository at Revision | `folder` | single | `requestBrowseRevision` |
  | Checkout Commit | `arrow.right.to.line` | single | detached checkout sheet |
  | Cherry Pick / Cherry Pick N Commits | `arrow.down.doc` | context not empty, no merge commits | cherry-pick oldest → newest (`cherryPickCommits`) |
  | AI Explain This Commit | `sparkles` | has primary | `requestExplain(primary)` |
  | — | | | |
  | Merge... | `arrow.triangle.merge` | single | merge sheet (both checkboxes on by default) |
  | Rebase... | `arrow.triangle.swap` | single | rebase sheet |
  | — | | | |
  | Squash Commits | `rectangle.compress.vertical` | `canSquashCommits` | squash sheet, suggested message = messages joined by newlines |
  | — | | | |
  | Tag... | `tag` | single | tag sheet |
  | Branch... | `arrow.triangle.branch` | single | branch sheet ("Checkout new branch" on by default) |
  | — | | | |
  | Reset to this commit | `arrow.counterclockwise` | single | fetch `currentBranch`, then open the reset sheet (Mixed by default) |
  | Reverse commit... | `arrow.uturn.backward` | single | revert confirmation alert |
  | — | | | |
  | Custom Actions ▸ | | | `CustomActionMenuContent` with surface `.selectedCommits` and the context hashes |
  | — | | | |
  | Copy Hash / Copy Hashes | `doc.on.doc` | context not empty | hashes joined by newlines |
  | Copy Message / Copy Messages | `doc.on.doc` | context not empty | messages joined by newlines |

- **Drag:**
  - Dragging a row: if it is in the selection, drag the whole selection; otherwise drag only that row. The dragged commit list comes from `draggedCommits` (§4.8).
  - Payload `GitDragPayload.commits(...)`, written to the pasteboard as `UTType.macgitGitDragPayload` and via `GitDragPayloadStore.set(payload)`.
  - The preview is **one** `CommitDragPreview` image (with a count badge), not per-row images.
  - Dragged rows render at 0.4 opacity until the drag ends. Ending a drag does **not** clear `GitDragPayloadStore` (`HistoryView.swift:2617`).

### 4.6 Sheets and alerts

Text, sizes and keyboard shortcuts (`cancelAction` / `defaultAction`) stay exactly as in `HistoryView.swift:374-612`:
- **Create Tag:** name field; "Create Tag" disabled when the trimmed name is empty.
- **Create Branch:** "From commit" line, name field, "Checkout new branch" checkbox.
- **Reset:** "This will reset '<branch>' to:", Soft / Mixed / Hard radio group; destructive "Reset" button.
- **Merge:** checkboxes "Commit merged changes immediately" and "Include messages from commits being merged in merge commit".
- **Rebase:** confirmation plus the warning "Make sure your changes have not been pushed to anyone else."
- **Detached checkout:** detached-HEAD explanation plus "Discard local changes" when there are uncommitted changes.
- **Revert:** "Reverse this commit?" alert with a "Revert" button.
- **Squash:** `SquashCommitsSheet`.
- **Error:** "Error" alert with the message.

Each operation runs through `runOperation(<progress message>)` with the current messages: "Checking out commit...", "Cherry-picking <hash7>..." / "Cherry-picking N commits...", "Merging commit...", "Rebasing onto commit...", "Squashing N commits...", "Creating tag <name>...", "Creating branch <name>...", "Resetting HEAD...".

### 4.7 Git and undo contract (must match exactly)

Every successful operation posts `.repositoryDidChange` with `userInfo["repositoryURL"]`, dismisses its sheet and clears the pending commit. Errors show the "Error" alert with `error.localizedDescription` unless stated otherwise.

"HEAD undo" means: after success, read `tipHash("HEAD")` again; if it differs from the old HEAD, register `GitUndoEntry(label, undo: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead), redo: <redo>)`.

| Operation | Call | Undo |
|---|---|---|
| Detached checkout | `checkoutCommit(hash, force: discardLocalChanges)` | none |
| Cherry-pick | `cherryPickCommits(hashes)` | HEAD undo, label "Cherry-pick <hash7>" / "Cherry-pick N commits", redo `.cherryPick(commit:)` / `.cherryPickCommits(commits:)` |
| Merge | `mergeCommit(hash, noCommit: !commitImmediately, log: includeMessages)` | HEAD undo, "Merge <hash7>", redo `.mergeCommit(commit:noCommit:log:)` |
| Rebase | `rebaseCommit(hash)` | HEAD undo, "Rebase onto <hash7>", redo `.rebaseOnto(commit:)` |
| Reset | `resetToCommit(hash, mode:)` | if HEAD changed: "Reset HEAD", undo `.resetHead(oldHead, mode: hard → .hard, otherwise .soft, expected: newHead)`, redo `.resetHead(hash, mode: resetMode.gitUndoMode, expected: oldHead)` |
| Revert | `revertCommit(hash)` | HEAD undo, "Revert <hash7>", redo `.revert(commit:)` |
| Squash | re-check `canSquashCommits` against the current HEAD, then `squashCommits(hashes, message:)` | if HEAD changed: "Squash N commits", undo `.resetHead(oldHead, .soft, expected: newHead)`, redo `.commit(message:noVerify: false, signOff: false)` |
| Tag | `createTag(name: trimmed, commit:, annotated: false, message: nil)` | none |
| Branch | `GitBranchUndoSupport().tip(of: hash)` first, then `createBranch(name: trimmed, checkout:, commit:)` | "Create branch <name>", undo `.deleteLocalBranch(name, force: true, expectedTip: startPoint)`, redo `.createLocalBranch(name, startPoint, checkout:)` |

Cherry-pick and revert failures are handled specially: `syncState.refresh`, then if `hasConflicts` → "<Cherry-pick|Revert> produced conflicts. Resolve them in the File status view, then continue or abort."; else if `inProgressOperation` is set → "<Cherry-pick|Revert> produced an empty commit. Open the File status view to skip or abort."; else `localizedDescription`. All three cases still post `.repositoryDidChange`.

Undo is registered only after the operation succeeds (per `AGENTS.md`).

### 4.8 Pure logic (`HistoryLoadPolicy`, same names and semantics)

- `historyScope(branchFilter:)`, `highlighting(for:)`, `highlightRootHash(for:commits:repositoryURL:)` (`.all` → nil; `.current` → decorated HEAD or `tipHash("HEAD")`; `.branch` → first commit or `tipHash(branch)`).
- `normalizedSearchQuery(_:)` (trim; fewer than 3 characters → empty).
- `resolvedHeadHash(from:)`, `tipCommit(for:in:)` (ref equals the branch name or `HEAD -> <branch>`), `commit(withHash:in:)`.
- `primaryHashForTableSelection(oldSelection:newSelection:previousPrimaryHash:visibleHashes:)`: exactly one added hash → that hash; several added → the one farthest from the previous primary; previous primary still selected → keep it; otherwise the last selected hash in display order.
- `canSquashCommits(_:selectedHashes:headHash:)`: at least 2 commits, first is HEAD, no merges, consecutive by first parent.
- `cherryPickCommits(from:)` (reversed order), `draggedCommits(startingAt:commits:selection:)` (uses `HistoryCommitSelection.draggedHashes`).
- `reloadTargetHash(reset:selectedCommitHash:newScrollTarget:)`.
- `loadKey(...)`, `emptyDetail(...)`: "Choose a base branch to compare against" / "No commits ahead of <base>" / "No matching commits ahead of <base>. Try author name, email, or commit ID" / "Repository may be empty" / "Try author name, email, or commit ID".

## 5. Intentionally removed

| Removed | Reason |
|---|---|
| Bidirectional pagination: `loadNewerHistoryIfNeeded`, `HistoryPagingState.startIndex` / `canLoadNewer` / `replaceWindow(startIndex:…)` | `startIndex` starts at 0 and all three assignments (`HistoryView.swift:1427`, `1531`, `1648`) assign a value ≤ the current one, so it is always 0. Dead code reached only by tests |
| `selectCommitFromNativeTap`, `selectionModifiers(from:)`, `contextMenuCommits` | No callers in the app; only tests call them |
| `isRestoringTableSelection`, `restoreSelectionIfTableClearsAfterReload` | Patches SwiftUI `Table` clearing selection when rows change. `NSTableView` keeps selection by index, and the model re-applies selection after each data change |
| Empty-selection interception on right-click, `isContextClick(onRows:)`, the `NSEvent` monitor | `NSTableView` does not change selection on right-click; use `clickedRow` |
| `suppressedCommitClickHash`, polling `pressedMouseButtons` | `NSTableView` reports drag end and does not send a double-click after a drag |
| `HistoryDragPreviewDataSource` (data source swap) | The controller is the data source and sets the preview directly |
| `HistoryTableScrollCoordinator`, `HistoryTableIntrospectionView`, `@AppStorage("history.tableColumns")` | Use AppKit column autosave and direct scrolling APIs |
| Complex viewport anchoring | Only one case remains (refresh preserving position): capture the first visible row hash plus offset, restore after reload |

## 6. New architecture

```
MainWindowView
└── HistoryScreen (SwiftUI, thin body – composition only)
    ├── BranchFilterBar
    ├── PersistentVSplit "HistoryMainSplit"
    │   ├── HistoryCommitTable                  (NSViewRepresentable → NSScrollView + HistoryNSTableView)
    │   │     └── HistoryCommitTableController  (data source / delegate / NSMenuDelegate / drag)
    │   └── HistoryCommitDetailView             (observes only HistoryCommitDetailModel)
    └── .historyActionPresentations(actions)    (observes only HistoryCommitActionController)

HistoryListModel              @Observable @MainActor – commits, graph, paging, cache, selection
HistoryCommitDetailModel      @Observable @MainActor – files, line counts, diff, full message, patch
HistoryCommitActionController @Observable @MainActor – pending commit, presentation, §4.7 execution
HistoryCommitContextMenu      SwiftUI View – menu content, built on right-click via NSHostingMenu
```

### 6.1 File locations

| File | Directory |
|---|---|
| `HistoryListModel.swift`, `HistoryCommitDetailModel.swift`, `HistoryCommitActionController.swift`, `HistoryCommitSelectionSink.swift` | `macgit/ViewModels/` |
| `HistoryLoadPolicy.swift`, `HistoryScreen.swift`, `HistoryCommitTable.swift`, `HistoryCommitTableController.swift`, `HistoryCommitTableCells.swift`, `HistoryRefBadgeView.swift`, `CommitGraphRowRenderer.swift`, `HistoryCommitDetailView.swift`, `HistoryCommitContextMenu.swift`, `HistoryActionSheets.swift` | `macgit/Views/History/` |

Delete when done: `HistoryView.swift`, `HistoryTableScrollCoordinator.swift`, `HistoryDragPreviewDataSource.swift`, `HistoryCommitMessageCell.swift`, `HistoryTableRow.swift`, and `BranchGraphRowCanvas.swift` if unused. Reduce `HistoryPagingState.swift` to one-directional paging.

### 6.2 `HistoryListModel`

```swift
@Observable @MainActor
final class HistoryListModel {
    // Inputs
    var repositoryURL: URL
    var branchFilter: HistoryBranchFilter
    var onlyThisBranch: Bool
    var baseBranch: String?
    var selectedBranch: String?
    func setSearchText(_ text: String)      // §4.2 debounce
    func setPageSize(_ size: Int)

    // Outputs (observed)
    private(set) var rows: HistoryRows
    private(set) var selection: HistoryCommitSelection
    private(set) var selectedCommit: Commit?     // may be a "pinned" commit no longer in rows (§4.3)
    private(set) var headHash: String?
    private(set) var phase: Phase                // .initialLoading, .idle, .refreshing (after 150 ms)
    private(set) var scrollRequest: HistoryScrollRequest?
    private(set) var dragActiveHashes: Set<String>
    var errorMessage: String?

    var loadKey: String { get }
    func load() async                            // driven by .task(id: loadKey)
    func refresh() async                         // §4.2 Refresh
    func clearCache()
    func loadMoreIfNeeded(lastVisibleRow: Int, visibleCount: Int)
    func applyTableSelection(orderedHashes: [String])
    func selectBranchTipIfPossible()
    func setDragActive(_ hashes: Set<String>)
    func consumeScrollRequest(_ token: UUID)
    var selectedHashesInDisplayOrder: [String] { get }
}

struct HistoryRows {
    enum Change { case reload(preserveViewport: Bool), appended(Range<Int>) }
    let commits: [Commit]
    let graphModel: CommitGraphModel?
    let hasMore: Bool
    let version: Int
    let change: Change
    let indexByHash: [String: Int]
}
struct HistoryScrollRequest: Equatable { let hash: String; let focus: Bool; let token: UUID }
```

- All internal state (tasks, cache, `CommitGraphGenerationState`, page-loading flag) is `@ObservationIgnored`.
- Each assignment to `rows` is a new immutable snapshot with `version + 1`; commits, graph and hasMore always change together.
- All hash lookups use `indexByHash`.

### 6.3 `HistoryCommitDetailModel`

```swift
@Observable @MainActor
final class HistoryCommitDetailModel {
    private(set) var commit: Commit?
    private(set) var fileChanges: [CommitFileChange]
    private(set) var lineCounts: [String: FileLineChangeCount]
    var selectedFile: CommitFileChange?          // didSet → load diff
    private(set) var diff: (commit: String, path: String, hunks: [DiffHunk])?
    private(set) var fullMessage: String?
    private(set) var isLoadingFullMessage: Bool
    var showingCommitInfo: Bool
    var fullFilePreview: CommitFilePreviewRequest?
    let patchController: CommitPatchController

    func show(_ commit: Commit?)                  // §4.4
    func resume()                                 // onAppear
    func suspend()                                // onDisappear
    func loadFullMessage()
    func patchDisabledReason(for files: [CommitFileChange]) -> String?
}
```

- Each part (files, line counts, patch eligibility) has its own "done" flag tied to the commit hash.
- Results are assigned in batches so the detail view renders once per part.

### 6.4 `HistoryCommitActionController`

```swift
@Observable @MainActor
final class HistoryCommitActionController {
    enum Presentation: Identifiable {
        case checkout(Commit, hasUncommittedChanges: Bool)
        case reset(Commit, branchName: String)
        case tag(Commit), branch(Commit), merge(Commit), rebase(Commit)
        case squash([Commit], message: String)
    }
    var presentation: Presentation?
    var revertCandidate: Commit?                 // Reverse alert
    var errorMessage: String?

    struct Dependencies {
        let repositoryURL: URL
        let undoManager: GitUndoManager?
        let syncState: SyncState?
        let runOperation: RepositoryOperationRunner
        let requestCheckout: (String, Bool) -> Void
        let requestExplain: (Commit) -> Void
        let requestBrowseRevision: (Commit) -> Void
        let runCustomAction: (UUID, [String]) -> Void
        let headHash: () -> String?
    }
    @ObservationIgnored var dependencies: Dependencies

    // Menu items (§4.5) + handleDoubleClick
    // Execution (§4.7): checkout(_, discard:), cherryPick(_:), merge(_, commitImmediately:, includeMessages:),
    //   rebase(_:), reset(_, mode:), revert(_:), squash(_, message:), createTag(_, name:), createBranch(_, name:, checkout:)
}
```

- Sheet inputs (tag / branch name, reset mode, checkboxes) are `@State` in each sheet view and passed to the execution function on confirm. The controller holds no input state.
- One helper `registerHeadUndo(label:oldHead:redo:)` serves all "HEAD undo" operations.

### 6.5 Table: `HistoryCommitTable` + `HistoryCommitTableController`

**Built once (`makeNSView`):**
- `HistoryNSTableView: NSTableView` with `gridStyleMask = .solidVerticalGridLineMask`, `usesAlternatingRowBackgroundColors`, `rowHeight = 24`, `allowsMultipleSelection`, `allowsColumnReordering`, `columnAutoresizingStyle = .noColumnAutoresizing`.
- Columns with identifiers `graph` / `message` / `author` / `date` / `commit` as in §4.1; `shouldReorderColumn` blocks `graph` and `message`; a header menu toggles the other three.
- `autosaveName = "HistoryCommitTable"`, `autosaveTableColumns = true`. Without an existing autosave, derive initial widths from the legacy ratios in `history.tableColumnRatios` if present (ratio × table width).
- `menu` with `delegate = controller`; `target` + `doubleAction`; `setDraggingSourceOperationMask(.copy, forLocal:)` for both values.
- `HistoryNSTableView.mouseDown` records `dragOriginRow`; `keyDown` handles Return / Enter.

**Update rules (`updateNSView` → `controller.apply`):**
1. Always store the latest references (`listModel`, `actions`, `customActionStore`, `textScale`) without reloading.
2. `rows.version` changed:
   - `.appended(range)` → `insertRows(at: range)` (handling the trailing loading row), viewport untouched.
   - `.reload(preserveViewport)` → if preserving, capture an anchor (first visible row hash + offset within the row) → `reloadData()` → restore the anchor via `indexByHash`.
3. Model selection differs from table selection → `selectRowIndexes(…, byExtendingSelection: false)` inside an `isApplyingModelSelection` guard so it does not echo back. Hashes not in rows are ignored.
4. New `scrollRequest.token` → scroll the row to the vertical center; if `focus`, `makeFirstResponder(tableView)`; then `consumeScrollRequest`.
5. `dragActiveHashes` changed → update `alphaValue` only for visible row views in old ∪ new sets.
6. `textScale` changed → `reloadData()`.

Nothing else triggers a reload. `updateNSView` reads only `rows`, `selection`, `scrollRequest` and `dragActiveHashes` from the model, so Observation tracks just those four properties.

**Cells** (plain AppKit, reused via `makeView(withIdentifier:owner:)`):
- `HistoryGraphCellView`: `draw(_:)` calls `CommitGraphRowRenderer` (§6.6); a `backgroundStyle` change sets `needsDisplay`.
- `HistoryMessageCellView`: an `NSStackView` with a pool of 3 `HistoryRefBadgeView`s, a "+N" label and the message label; reconfigured by hiding/showing and assigning text, never by creating views.
- `HistoryTextCellView`: one `NSTextField` for Author / Date / Commit; one shared date formatter.
- `HistoryLoadingCellView`: small spinner plus "Loading older commits…".
- Tooltips via `toolTip`.

**Pagination:** observe the clip view's `boundsDidChangeNotification` → `rows(in: visibleRect)` → `listModel.loadMoreIfNeeded(lastVisibleRow:visibleCount:)`. Also call it once after each new `rows` snapshot is applied.

**Selection:** `tableViewSelectionDidChange` (ignored while `isApplyingModelSelection`) → `listModel.applyTableSelection(orderedHashes:)`. `selectionIndexesForProposedSelection` excludes the loading row.

**Context menu:** in `menuNeedsUpdate`, an invalid `clickedRow` or the loading row yields an empty menu; an unselected `clickedRow` becomes the sole selection; then build `NSHostingMenu(rootView: HistoryCommitContextMenu(...))` from the selection in display order and move its items into `menu`.

**Double-click / Return:** `doubleAction` uses `clickedRow`; Return uses the primary commit → `actions.handleDoubleClick`.

**Drag:** `pasteboardWriterForRow` returns an `NSPasteboardItem` only for `dragOriginRow` (a single item carrying the full payload); `draggingSession(_:willBeginAt:forRowIndexes:)` sets the `CommitDragPreview` image (rendered with `ImageRenderer`, matching the table's appearance), sets `draggingFormation = .none` and calls `setDragActive`; `draggingSession(_:endedAt:operation:)` → `setDragActive([])`.

### 6.6 Shared drawing

- `CommitGraphRowRenderer.draw(_ geometry:, rowIndex:, in: CGContext, dotBackground: NSColor)`: Core Graphics, with the same constants (row height 24, lane width 14, dot size 8) and dot drawing as `BranchGraphCanvas.drawDot`; line colors from `BranchGraphCanvas.lineColor` (add an `NSColor` variant if needed).
- `RefLabelStyle` is extracted from `RefLabel` (`displayText`, `isTag`, icon, foreground / background colors). Both `RefLabel` (SwiftUI, used in the detail header) and `HistoryRefBadgeView` (AppKit) use it, so badge appearance has a single source.

### 6.7 `HistoryScreen`

- Parameters: `repositoryURL`, `selectedBranch`, `@Binding branchFilter`, `@Binding includeRemotes`, `dependencies`, `selectionSink`. No `@EnvironmentObject AppState`. `CustomActionStore` still comes from the environment and is passed only to the table (used when building the menu).
- `@State` holds the three models plus `BranchFilterBar` state (`onlyThisBranch`, `baseBranch`, `searchText`).
- The body only composes the §4.1 layout and wires inputs to the model through `.onChange`, `.task(id: listModel.loadKey)` and `.onReceive` for the three notifications.
- `.onChange(of: listModel.selectedCommit?.hash)` → `detailModel.show(...)`; `.onChange(of: listModel.selectedHashesInDisplayOrder)` → `selectionSink.update(...)`.
- `.onAppear` → `detailModel.resume()`; `.onDisappear` → `detailModel.suspend()` and cancel the search debounce.
- Each body evaluation only assigns `actions.dependencies` (`@ObservationIgnored`).

### 6.8 MainWindow integration

- Replace `HistoryView(...)` at `MainWindowView.swift:1376` with `HistoryScreen(...)`, passing `$appState.historyBranchFilter`, `$appState.historyIncludeRemotes` and `Dependencies` built from the existing closures.
- `HistoryCommitSelectionSink` (`@Observable`, held in MainWindow `@State`, `update` assigns only when the value changes) replaces `customActionCommitHashes`. `customActionCommandState` reads `sink.commitHashes`.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Implicit behavior lost in the rewrite | §4 is the complete list with old line references; the checklist at the end of the plan is used when running the app |
| Visual drift from SwiftUI `Table` | Same metrics: 24 pt rows, small control size, callout × textScale, `secondaryLabelColor` / `tertiaryLabelColor`; badges share `RefLabelStyle` |
| Wrong git / undo behavior | §4.7 is mandatory; review that part against the old code before deleting `HistoryView` |
| Saved column layout lost | Derive initial widths from the legacy ratios when no autosave exists |
| Drop targets depend on item count | Commit drops on the sidebar read `GitDragPayloadStore.currentPayload()` (`SidebarView+DragDrop.swift`); `dropDestination(for: GitDragPayload.self)` in `FileStatusView` handles stashes only. Re-check during the drag task |
| Existing tests reference `HistoryView.xxx` | Functions with unchanged semantics → change the prefix to `HistoryLoadPolicy`; tests for removed functions (§5) → delete |
