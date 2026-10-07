# History Screen Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thay `HistoryView` (2681 dòng, SwiftUI `Table` + nhiều lớp lách) bằng màn hình mới tách model / table AppKit / detail / action, giữ nguyên UI và hành vi click, double-click, right-click, drag trên commit row.

**Spec:** `docs/superpowers/specs/2026-10-07-history-screen-rewrite-design.md` — đọc trước khi làm; mọi quy tắc invalidation và hành vi cần giữ nằm ở đó.

**Architecture:** `HistoryScreen` (SwiftUI mỏng) ghép `BranchFilterBar`, `HistoryCommitTable` (`NSViewRepresentable` bọc `NSTableView`, controller làm dataSource / delegate / menu / drag) và `HistoryCommitDetailView`. State nằm trong 3 model `@Observable @MainActor`: `HistoryListModel`, `HistoryCommitDetailModel`, `HistoryCommitActionController`.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSTableView`), Observation, `GitStatusService`.

**Phạm vi plan:** chỉ các thay đổi code. Không có bước đo hiệu năng hay viết test mới. Test hiện có chỉ được sửa tham chiếu để compile.

**Quy ước:**
- Branch: `codex/history-rewrite`.
- File Swift mới bắt đầu bằng `// SPDX-License-Identifier: AGPL-3.0-or-later`.
- Project dùng synchronized folder, thêm / xoá file không cần sửa `macgit.xcodeproj`.
- Code cũ giữ nguyên tới Task 8 để luôn có thể so sánh; `HistoryView` chỉ bị gỡ khỏi MainWindow ở Task 7.
- Cuối mỗi task: `rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` phải pass.

---

### Task 1: Tách logic thuần và phần vẽ dùng chung

**Files:**
- Create: `macgit/Views/History/HistoryLoadPolicy.swift`
- Create: `macgit/Views/History/CommitGraphRowRenderer.swift`
- Modify: `macgit/Views/History/RefLabel.swift`
- Modify: `macgit/Views/History/BranchGraphRowCanvas.swift` (tạm, tới khi xoá ở Task 8)

- [ ] **Step 1: `HistoryLoadPolicy`** — `enum HistoryLoadPolicy` chứa các hàm static thuần hiện nằm trong `HistoryView`, chuyển nguyên thân hàm:
  - `HistoryScope`, `HistorySnapshot` (đổi tên thành `HistoryLoadPolicy.Scope` / `.Snapshot`)
  - `historyScope(branchFilter:)`, `reloadTargetHash`, `highlighting(for:)`, `highlightRootHash(for:commits:repositoryURL:)`
  - `primaryHashForTableSelection`, `normalizedSearchQuery`, `resolvedHeadHash`, `tipCommit(for:in:)`, `commit(withHash:in:)`
  - `contextMenuCommits`, `cherryPickCommits(from:)`, `draggedCommits(startingAt:commits:selection:)`, `canSquashCommits`
  - Thêm `loadKey(filter:searchQuery:loadSize:onlyThisBranch:baseBranch:) -> String` (từ `historyLoadKey`) và `emptyDetail(...)` (từ `historyEmptyDetail`).
  - Bỏ `selectionModifiers(from:)` và `selectCommitFromNativeTap` nếu sau Task 5 không còn nơi dùng; giữ tạm ở bước này.
- [ ] **Step 2:** Trong `HistoryView`, cho các static cũ forward sang `HistoryLoadPolicy` (một dòng mỗi hàm) để `HistoryView` và test hiện có vẫn compile. Phần forward bị xoá cùng `HistoryView` ở Task 8.
- [ ] **Step 3: `RefLabelStyle`** — trong `RefLabel.swift`, tách `displayText`, `isTag`, icon name, màu nền / màu chữ (dạng `NSColor` + opacity) thành `struct RefLabelStyle { init(text:graphColorIndex:) }`. `RefLabel` dùng lại `RefLabelStyle`; giao diện SwiftUI không đổi. Màu graph lấy qua `GraphPalette` (thêm accessor `nsColor(for:)` nếu `GraphPalette` mới chỉ có `Color`).
- [ ] **Step 4: `CommitGraphRowRenderer`** — `enum CommitGraphRowRenderer` với
  ```swift
  static func draw(_ geometry: CommitGraphRowGeometry, rowIndex: Int,
                   in context: CGContext, bounds: CGRect, dotBackground: NSColor)
  ```
  Port `BranchGraphRowCanvas.drawRow` + `BranchGraphCanvas.drawDot` sang CoreGraphics: `stroke.path.cgPath`, line width 2.2, round cap / join, màu từ `BranchGraphCanvas.lineColor(colorIndex:isHighlighted:)` (thêm biến thể trả `NSColor`), dịch theo `rowOffset = rowIndex * rowHeight` giống bản `Canvas`. Hằng số row height / lane width / dot size đọc từ `BranchGraphRowCanvas` (chuyển sang `CommitGraphRowRenderer` ở Task 8).
- [ ] **Step 5:** Build.

### Task 2: `HistoryListModel`

**Files:**
- Create: `macgit/ViewModels/HistoryListModel.swift`

- [ ] **Step 1: Kiểu dữ liệu**
  ```swift
  struct HistoryRowsSnapshot {
      enum Change { case reload(preserveViewport: Bool), appended(Range<Int>), prepended(count: Int) }
      let commits: [Commit]
      let graphModel: CommitGraphModel?
      let hasMore: Bool
      let version: Int
      let change: Change
      let hashIndex: [String: Int]
  }
  struct HistoryScrollRequest: Equatable { let hash: String; let focus: Bool; let token: UUID }
  ```
- [ ] **Step 2: Khung class** theo spec §5.2: inputs (`repositoryURL`, `branchFilter`, `onlyThisBranch`, `baseBranch`, `searchText`, `selectedBranch`, `pageSize`), outputs `private(set)`, các state nội bộ đánh dấu `@ObservationIgnored` (`graphGenerationState`, `paging`, `historyCache`, các `Task`, `isRestoringSelection`). Chỉ những gì view đọc mới được observe.
- [ ] **Step 3: Load** — chuyển nguyên `loadHistory(reset:preservingSelectionAndScroll:)`, `applyCachedSnapshot`, `loadOlderHistoryIfNeeded`, `loadNewerHistoryIfNeeded`, `historyPage` từ `HistoryView.swift:1219-1745`. Thay đổi bắt buộc:
  - `appState.historyBranchFilter` → `branchFilter`; `historyOnlyThisBranch` / `historyBaseBranch` → thuộc tính model.
  - Bỏ các `await MainActor.run { }` (class đã `@MainActor`).
  - Thay cặp `commits` + `graphModel` + `graphGenerationState` bằng một hàm `publish(commits:graph:hasMore:change:)` tăng `version` và dựng `hashIndex`. Append trang cũ → `.appended(oldCount..<newCount)`; `loadNewer` → `.prepended(count: newCount - oldCount)`; còn lại → `.reload(preserveViewport: preservingSelectionAndScroll)`.
  - `tableScrollCoordinator.viewportAnchor` / `restoreViewportAnchor` → bỏ khỏi model (table tự xử lý theo `change`).
  - `scrollTarget = hash` → `scrollRequest = HistoryScrollRequest(hash:focus:false, token: UUID())`.
  - `tableSelection = ...` → bỏ; selection chỉ còn `selection: HistoryCommitSelection`.
  - `restoreSelectionIfTableClearsAfterReload` → bỏ (table AppKit không tự xoá selection khi reload; controller áp lại selection từ model sau mỗi snapshot).
- [ ] **Step 4: Search debounce + refresh indicator** — chuyển `scheduleHistorySearchDebounce`, `scheduleHistoryRefreshIndicator`, `cancelHistoryRefreshIndicator`. `activeSearchQuery` là `private(set)`.
- [ ] **Step 5: API selection**
  - `applyNativeSelection(orderedHashes:previous:)`: port `applyTableSelection` (bỏ nhánh `isContextClick`); giữ nhánh "primary nằm ngoài cửa sổ hiện tại thì giữ detail".
  - `selectForContextClick(hash:)` (từ closure `startContextClickMonitoring`).
  - `selectBranchTip(_:)` (từ `HistoryView.swift:2510`) — phát `scrollRequest` với `focus: true`.
  - `selectedHashesInDisplayOrder` tính từ `selection.selectedHashes` theo `hashIndex`.
- [ ] **Step 6: Paging theo viewport** — `viewportDidChange(visibleRows: Range<Int>)` port `handleHistoryCommitCellAppearance` (cùng ngưỡng `max(pageSize, visible.count * 3)`), bỏ phụ thuộc `tableScrollCoordinator.visibleRowRange()`.
- [ ] **Step 7: Phụ trợ** — `setDragActive(_ hashes: Set<String>)`, `consumeScrollRequest(_ token: UUID)`, `clearCaches()`, `setPageSize(_:)` (từ `onChange(of: historyLoadSizeRaw)`), `loadKey` computed dùng `HistoryLoadPolicy.loadKey`.
- [ ] **Step 8:** Build.

### Task 3: Detail model và detail view

**Files:**
- Create: `macgit/ViewModels/HistoryCommitDetailModel.swift`
- Create: `macgit/Views/History/HistoryCommitDetailView.swift`

- [ ] **Step 1: Model** theo spec §5.3. Chuyển `loadFileChanges(for:resuming:)`, `loadDiff(for:in:)`, `commitPatchDisabledReason(for:)`, `showCommitInfo(for:)` từ `HistoryView.swift:1021-1043`, `1747-1851`. Các `UUID` load ID và task → `@ObservationIgnored`.
- [ ] **Step 2: `show(_ commit:)`** — set `commit`, reset `showingCommitInfo` / `fullMessage` (như `onChange(of: selectedCommit)` hiện tại), huỷ task, rồi `Task { try await Task.sleep(for: .milliseconds(80)); await loadFileChanges(...) }`. Nếu cùng hash với commit đang hiển thị thì không làm gì.
- [ ] **Step 3: Gán theo lô** — trong `loadFileChanges`, gán `fileChanges`, `lineCounts`, `selectedFile`, cờ loaded trong cùng một đoạn đồng bộ sau khi có đủ kết quả. `selectedFile` có `didSet` gọi `loadDiff`.
- [ ] **Step 4: `resumeIfCancelled()` / `cancelLoads()`** — port logic `onAppear` (`HistoryView.swift:256-265`) và `onDisappear`.
- [ ] **Step 5: View** — chuyển `commitDetailPanel`, `commitInfoHeader`, `commitDiffViewer`, `displayCommitMessage`, `updateCommitInfoCursor`, `copyToPasteboard` (`HistoryView.swift:820-1048`) vào `HistoryCommitDetailView(model:repositoryURL:undoManager:syncState:runOperation:)`. Các binding (`$selectedFile`, `$showingCommitInfo`) lấy qua `@Bindable var model`.
- [ ] **Step 6:** Gắn vào detail view: `.replacingSheet(item: $model.fullFilePreview)` với `CommitFilePreviewSheet` (cần `previewAvailableSize` — đo bằng `onGeometryChange` ngay trong view này), `.replacingSheet(item: $model.patchController.prepared)` với `CommitPatchReviewSheet`, alert "Selected changes". Chuyển nguyên từ `HistoryView.swift:307-351`.
- [ ] **Step 7:** Build.

### Task 4: Action controller, sheet và context menu

**Files:**
- Create: `macgit/ViewModels/HistoryCommitActionController.swift`
- Create: `macgit/Views/History/HistoryActionSheets.swift`
- Create: `macgit/Views/History/HistoryCommitContextMenu.swift`

- [ ] **Step 1: Controller** theo spec §5.4. `Presentation` enum (`checkout`, `reset`, `tag`, `branch`, `merge`, `rebase`, `squash(commits:message:)`) với `id`. `dependencies` là `@ObservationIgnored var`.
- [ ] **Step 2: `perform*`** — chuyển nguyên `performCheckoutCommit`, `registerHeadChangingUndo`, `performCherryPick`, `performMerge`, `performRebase`, `performReset`, `performRevert`, `performSquash`, `performCreateTag`, `performCreateBranch` (`HistoryView.swift:1952-2320`). Thay `showingXxx = false` bằng `presentation = nil`; `repositoryURL` / `undoManager` / `syncState` lấy từ `dependencies`; bỏ `await MainActor.run`.
- [ ] **Step 3: Request methods** — mỗi mục menu một hàm (`requestCheckoutCommit`, `cherryPick`, `requestMerge`, `requestRebase`, `requestSquash`, `requestTag`, `requestBranch`, `requestReset`, `requestRevert`, `explain`, `browseRevision`, `copyHashes`, `copyMessages`), thân hàm lấy từ action của từng `Button` trong `commitContextMenu(for:)` (`HistoryView.swift:1069-1213`). `requestReset` vẫn lấy `currentBranch` trước khi mở sheet.
- [ ] **Step 4: `handleDoubleClick(_:)`** — port `handleCommitDoubleClick` (`HistoryView.swift:1979-1997`).
- [ ] **Step 5: Sheets** — chuyển `tagSheet`, `branchSheet`, `resetSheet`, `mergeConfirmationSheet`, `rebaseConfirmationSheet`, `checkoutConfirmationSheet` (`HistoryView.swift:374-612`) thành các `struct` view nhận `@Bindable var controller`. Thêm modifier:
  ```swift
  extension View {
      func historyActionPresentations(_ controller: HistoryCommitActionController) -> some View
  }
  ```
  gồm một `.replacingSheet(item: $controller.presentation)` switch theo case (squash dùng `SquashCommitsSheet`), alert "Reverse this commit?", alert "Error". Giữ nguyên text, kích thước, keyboard shortcut.
- [ ] **Step 6: Context menu view** — `struct HistoryCommitContextMenu: View` nhận `contextCommits: [Commit]`, `primaryCommit: Commit?`, `headHash: String?`, `repositoryURL: URL`, `controller`, `customActionStore`. Body = nội dung `commitContextMenu(for:)` với action gọi `controller.xxx`. Giữ nguyên thứ tự, divider, icon, `.disabled`. Custom Actions submenu dùng `CustomActionMenuContent` như cũ, `onRun` → `controller.dependencies.runCustomAction`.
- [ ] **Step 7:** Build.

### Task 5: Table AppKit

**Files:**
- Create: `macgit/Views/History/HistoryCommitTable.swift`
- Create: `macgit/Views/History/HistoryCommitTableController.swift`
- Create: `macgit/Views/History/HistoryCommitTableCells.swift`
- Create: `macgit/Views/History/HistoryRefBadgeView.swift`

- [ ] **Step 1: Representable**
  ```swift
  struct HistoryCommitTable: NSViewRepresentable {
      let listModel: HistoryListModel
      let actions: HistoryCommitActionController
      let customActionStore: CustomActionStore
      let repositoryURL: URL
      let textScale: CGFloat
      func makeCoordinator() -> HistoryCommitTableController
      func makeNSView(context:) -> NSScrollView
      func updateNSView(_:context:)
  }
  ```
  Body của `updateNSView` chỉ đọc `listModel.rows`, `listModel.selection`, `listModel.scrollRequest`, `listModel.dragActiveHashes` rồi gọi `controller.apply(...)` — để Observation chỉ theo dõi đúng 4 thuộc tính này.
- [ ] **Step 2: `HistoryNSTableView`** (cùng file) — subclass `NSTableView`: ghi `dragOriginRow` trong `mouseDown`; `keyDown` bắt Return / Enter → `onPrimaryAction`; trả `menu` cho right-click mặc định.
- [ ] **Step 3: Dựng bảng trong `makeNSView`** theo spec §5.5 "Dựng bảng": style, grid, alternating rows, row height 24, multiple selection, 5 cột với identifier `graph` / `message` / `author` / `date` / `commit` và min / width như spec; header menu ẩn/hiện 3 cột phụ; `autosaveName = "HistoryCommitTable"`, `autosaveTableColumns = true`; migration một lần từ `history.tableColumnRatios` (port phần tính ratio trong `HistoryTableScrollCoordinator.init`) khi `UserDefaults` chưa có key autosave `NSTableView Columns HistoryCommitTable`. `tableView(_:shouldReorderColumn:toColumn:)` chặn `graph` / `message`. `clipView.postsBoundsChangedNotifications = true`.
- [ ] **Step 4: Controller — data source** — `numberOfRows = commits.count + (hasMore ? 1 : 0)`; `viewFor(tableColumn:row:)` trả cell theo cột, loading row chỉ có cell ở cột `message`; `isGroupRow` = false; `rowViewForRow` dùng `NSTableRowView` mặc định.
- [ ] **Step 5: Controller — `apply(rows:selection:scrollRequest:dragActive:textScale:)`** đúng 6 quy tắc ở spec §5.5 "updateNSView". Lưu `appliedVersion`, `appliedTextScale`, `appliedDragActive`, `lastScrollToken`. Áp selection trong khối `isApplyingModelSelection`. Cuộn giữa: port `scrollToRowWhenReady` / phần center trong `HistoryTableScrollCoordinator` (dùng `rect(ofRow:)` + `clipView.scroll(to:)` + `reflectScrolledClipView`). `focus: true` → `window?.makeFirstResponder(tableView)`.
- [ ] **Step 6: Controller — viewport** — observer `NSView.boundsDidChangeNotification` của clip view → `rows(in: visibleRect)` → nếu khác lần trước thì `listModel.viewportDidChange(visibleRows:)`. Gọi thêm một lần ở cuối `apply` khi `version` đổi. Gỡ observer trong `deinit` / `dismantleNSView`.
- [ ] **Step 7: Controller — selection** — `tableViewSelectionDidChange` theo spec; `selectionIndexesForProposedSelection` loại loading row.
- [ ] **Step 8: Controller — context menu** — `NSMenuDelegate.menuNeedsUpdate` theo 4 bước ở spec §5.5 "Context menu". Dựng `NSHostingMenu(rootView: HistoryCommitContextMenu(...).environmentObject(customActionStore))`, chuyển các item sang `menu` (xoá item cũ trước). `primaryCommit` = `listModel.selectedCommit` nếu thuộc context, ngược lại commit đầu.
- [ ] **Step 9: Controller — double-click** — `tableView.target = self`, `doubleAction = #selector(handleDoubleClick)`; bỏ qua `clickedRow < 0` và loading row. `onPrimaryAction` của Return dùng cùng đường.
- [ ] **Step 10: Cells** (`HistoryCommitTableCells.swift`):
  - `HistoryGraphCellView: NSTableCellView` — giữ `geometry` + `rowIndex`, `draw(_:)` gọi `CommitGraphRowRenderer.draw`; override `backgroundStyle` didSet → `needsDisplay = true`; vẽ tràn 4pt trên / dưới (khung cell cao 24, không clip theo row insets — tắt `clipsToBounds` hoặc đặt frame cell bằng full row height).
  - `HistoryMessageCellView` — `NSStackView` (spacing 4) chứa pool 3 `HistoryRefBadgeView` + `NSTextField` "+N" + `NSTextField` message (lineBreakMode `.byTruncatingTail`, 1 dòng). `configure(commit:graphColorIndex:textScale:)` chỉ ẩn/hiện và cập nhật view trong pool.
  - `HistoryTextCellView` — một `NSTextField` cấu hình theo kiểu (`author` / `date` / `commit`). `static let dateFormatter` / `Date.FormatStyle` dùng chung.
  - `HistoryLoadingCellView` — `NSProgressIndicator` (small, spinning) + label "Loading older commits…" (caption × textScale, secondary).
  - Font: `NSFont.preferredFont(forTextStyle: .callout)` scale theo `textScale`; màu `secondaryLabelColor` / `tertiaryLabelColor`.
  - Tooltip đặt qua `toolTip` của text field.
- [ ] **Step 11: `HistoryRefBadgeView`** — `NSView` vẽ capsule + `NSImage(systemSymbolName:)` 10pt semibold + text 11pt semibold × textScale theo `RefLabelStyle`; `intrinsicContentSize` theo text; đổi màu khi `backgroundStyle == .emphasized` (nhận từ cell cha).
- [ ] **Step 12:** Build.

### Task 6: Drag commit từ table

**Files:**
- Modify: `macgit/Views/History/HistoryCommitTableController.swift`

- [ ] **Step 1:** `tableView.setDraggingSourceOperationMask(.copy, forLocal: true)` và `(.copy, forLocal: false)` trong `makeNSView`.
- [ ] **Step 2: `pasteboardWriterForRow`** — chỉ cho `row == tableView.dragOriginRow` (và không phải loading row). Tính selection kéo như `makeCommitDragPayload` (`HistoryView.swift:2572-2601`): row thuộc selection thì kéo cả selection, không thì chỉ row đó; payload = `GitDragPayload.commits(HistoryLoadPolicy.draggedCommits(...), repositoryURL:)`. Trả `NSPasteboardItem` với `setData(try GitDragPayload.encodeTransferData(payload), forType: .init(UTType.macgitGitDragPayload.identifier))`; `GitDragPayloadStore.set(payload)`; lưu `pendingDragPreview` và `pendingDragHashes`.
- [ ] **Step 3: `draggingSession(_:willBeginAt:forRowIndexes:)`** — render ảnh bằng code của `HistoryDragPreviewDataSource.prepare` + `replacePreview` (chuyển sang controller), `draggingFormation = .none`; `listModel.setDragActive(pendingDragHashes)`.
- [ ] **Step 4: `draggingSession(_:endedAt:operation:)`** — `listModel.setDragActive([])`; không xoá `GitDragPayloadStore`.
- [ ] **Step 5:** Rà các drop handler nhận commit (`SidebarView+DragDrop.swift` và nơi khác gọi `GitDragPayloadStore.currentPayload()` hoặc `dropDestination(for: GitDragPayload.self)`) để chắc chắn chúng hoạt động với một dragging item. Ghi chú kết quả vào mô tả PR.
- [ ] **Step 6:** Build.

### Task 7: `HistoryScreen` và tích hợp MainWindow

**Files:**
- Create: `macgit/Views/History/HistoryScreen.swift`
- Create: `macgit/ViewModels/HistoryCommitSelectionSink.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: `HistoryCommitSelectionSink`**
  ```swift
  @Observable @MainActor
  final class HistoryCommitSelectionSink {
      private(set) var commitHashes: [String] = []
      func update(_ hashes: [String]) { guard hashes != commitHashes else { return }; commitHashes = hashes }
  }
  ```
- [ ] **Step 2: `HistoryScreen`** theo spec §5.7. `init` tạo 3 model bằng `State(initialValue:)` (page size đọc từ `UserDefaults` như `HistoryView.init`). Body:
  - `BranchFilterBar(repositoryURL:selectedFilter: $branchFilter, includeRemotes: $includeRemotes, onlyThisBranch: $onlyThisBranch, baseBranch: $baseBranch, searchText: $searchText)`
  - `isInitialLoading && commits.isEmpty` → `ProgressView("Loading history…")`; rỗng → `EmptyStateView` với `HistoryLoadPolicy.emptyDetail`; ngược lại `ZStack(alignment: .top) { PersistentVSplit("HistoryMainSplit", 200/180) { HistoryCommitTable … } bottom: { HistoryCommitDetailView … } ; refresh capsule }`.
  - `.id("history")`, frame, background như cũ.
- [ ] **Step 3: Nối sự kiện** trong `HistoryScreen`:
  - `.onChange` của `branchFilter`, `onlyThisBranch`, `baseBranch`, `searchText`, `selectedBranch`, `historyLoadSizeRaw` → gán vào `listModel` (search đi qua debounce của model).
  - `.task(id: listModel.loadKey) { await listModel.loadKeyDidChange() }`.
  - `.onReceive` `.repositoryDidChange` + `.repositoryLocalStateDidRefresh` (lọc `repositoryURL`) → `clearCaches()` + `refresh(preservingSelectionAndScroll: true)`; `.advancedClearSessionCaches` → như cũ.
  - `.onChange(of: listModel.selectedCommit?.hash)` → `detailModel.show(listModel.selectedCommit)`.
  - `.onChange(of: listModel.selectedHashesInDisplayOrder)` → `selectionSink.update(...)`.
  - `.onAppear` / `.onDisappear` theo spec.
  - Mỗi lần body chạy: `actions.dependencies = dependencies` (ignored by Observation).
  - `.historyActionPresentations(actions)` và alert lỗi của `listModel.errorMessage`.
- [ ] **Step 4: MainWindow**
  - Thêm `@State private var historySelectionSink = HistoryCommitSelectionSink()`; bỏ `customActionCommitHashes` (`MainWindowView.swift:204`), `customActionCommandState` (`:825-829`) đọc `historySelectionSink.commitHashes`.
  - Thay khối `HistoryView(...)` (`:1376-1397`) bằng `HistoryScreen(repositoryURL:selectedBranch: selectedBranchName, branchFilter: $appState.historyBranchFilter, includeRemotes: $appState.historyIncludeRemotes, dependencies: .init(repositoryURL:undoManager:syncState:runOperation: runRepositoryOperation, requestCheckout: checkoutRequest, requestExplain: explainCommitWithRepositoryAI, requestBrowseRevision: { … }, runCustomAction: { … }), selectionSink: historySelectionSink)` — closure giữ nguyên nội dung hiện tại.
  - Tìm các chỗ khác ghi `customActionCommitHashes` (reset khi đổi màn hình / repo) và chuyển sang `historySelectionSink.update([])`.
- [ ] **Step 5:** Build.

### Task 8: Dọn code cũ

**Files:**
- Delete: `macgit/Views/History/HistoryView.swift`, `HistoryTableScrollCoordinator.swift`, `HistoryDragPreviewDataSource.swift`, `HistoryCommitMessageCell.swift`, `HistoryTableRow.swift`
- Delete (nếu không còn nơi dùng sau khi grep): `macgit/Views/History/BranchGraphRowCanvas.swift`
- Modify: `macgitTests/HistoryViewTests.swift`, `macgitTests/HistoryCommitSelectionTests.swift`, `macgitTests/HistoryPaginationTests.swift`; Delete: `macgitTests/HistoryTableScrollCoordinatorTests.swift`

- [ ] **Step 1:** Grep `HistoryView`, `HistoryTableScrollCoordinator`, `HistoryTableIntrospectionView`, `HistoryTableRow`, `BranchGraphRowCanvas`, `HistoryCommitMessageCell` trên toàn repo; xoá file khi không còn tham chiếu ngoài test. Chuyển các hằng số row height / lane width / dot size còn được dùng sang `CommitGraphRowRenderer`.
- [ ] **Step 2:** Test: đổi `HistoryView.xxx` → `HistoryLoadPolicy.xxx` để compile; xoá `HistoryTableScrollCoordinatorTests.swift` (đối tượng test không còn). Không viết test mới.
- [ ] **Step 3:** Xoá các key `UserDefaults` không còn đọc (`history.tableColumns` của `@AppStorage TableColumnCustomization`, `history.tableColumnLayout`) khỏi code; không chủ động xoá giá trị đã lưu của người dùng.
- [ ] **Step 4:** Build. `rtk git diff --check`.

---

## Thứ tự & phụ thuộc

```
Task 1 ──┬─> Task 2 ──┐
         ├─> Task 3 ──┼─> Task 5 ─> Task 6 ─> Task 7 ─> Task 8
         └─> Task 4 ──┘
```

Task 2, 3, 4 độc lập với nhau sau Task 1 và có thể làm song song. Task 5 cần cả ba. `HistoryView` vẫn chạy trong app tới hết Task 6; Task 7 mới chuyển MainWindow sang màn hình mới.

## Checklist giữ hành vi (dùng khi review diff)

- [ ] Click, Shift-click, Cmd-click, phím ↑↓ / Shift+↑↓ cập nhật selection và detail như cũ; primary commit theo `primaryHashForTableSelection`.
- [ ] Right-click row chưa chọn → chọn row đó; right-click row đã chọn → giữ multi-selection.
- [ ] Toàn bộ mục context menu, thứ tự, điều kiện enable, Custom Actions, Copy giống `commitContextMenu(for:)`.
- [ ] Double-click / Return → checkout branch ref hoặc sheet checkout detached.
- [ ] Drag một / nhiều commit sang sidebar; preview một ảnh có badge; row mờ khi kéo.
- [ ] Phân trang xuống và lên; "Loading older commits…" row; giữ selection + viewport khi refresh.
- [ ] Filter branch, include remotes, only-this-branch, search, history load size, cache 3 snapshot.
- [ ] Đổi branch ở sidebar (filter `.all`) → chọn tip, cuộn tới, focus bảng.
- [ ] Reflog "Show Commit" vẫn mở History đúng commit.
- [ ] Ẩn/hiện cột Author / Date / Commit, kéo độ rộng cột, layout được lưu.
- [ ] Toolbar Custom Actions nhận đúng commit đang chọn.
