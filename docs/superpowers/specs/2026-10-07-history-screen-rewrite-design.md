# History Screen Rewrite — Design Spec

**Ngày:** 2026-10-07
**Phạm vi:** Viết lại màn hình History (`macgit/Views/History/HistoryView.swift` và các lớp lách SwiftUI `Table` đi kèm). Giữ nguyên giao diện, hành vi click / double-click / right-click / drag trên từng commit row.
**Plan triển khai:** `docs/superpowers/plans/2026-10-07-history-screen-rewrite-plan.md`

---

## 1. Bối cảnh

History và Reflog cùng dùng SwiftUI `Table` + detail panel, nhưng History lag rõ rệt khi click chọn commit, điều hướng bằng phím và scroll. Nguyên nhân nằm ở kiến trúc, không phải ở `Table`:

| Vấn đề | Vị trí hiện tại |
|---|---|
| ~60 `@State` trong một struct 2681 dòng; detail (`fileChanges`, `commitLineCounts`, `diffHunks`, `selectedFile`, `showingCommitInfo`…) đổi là toàn bộ body, kể cả `Table` rows builder, bị đánh giá lại | `HistoryView.swift:47-122` |
| `@EnvironmentObject AppState` (29 `@Published`) — mọi thay đổi AppState không liên quan cũng invalidate History | `HistoryView.swift:42` |
| Mỗi lần đổi selection gọi `onCustomActionSelectionChanged` → ghi `@State` của `MainWindowView` → MainWindow render lại → `HistoryView` được dựng lại với closure mới → body chạy lại lần nữa | `HistoryView.swift:706-709`, `MainWindowView.swift:1385` |
| Nhiều phép O(n) mỗi click: `Set(commits.map(\.hash))` trong binding setter, `applyTableSelection`, context menu builder | `HistoryView.swift:1853-1925`, `1052` |
| Cell nặng: `GeometryReader` + `NSViewRepresentable` introspection trong mọi message cell, `Canvas` per row, 3 `.help()` per row, `onAppear` per cell để phân trang | `HistoryCommitMessageCell.swift`, `HistoryView.swift:725-816`, `1937` |
| `activeDragCommitHashes` được đọc trong mọi cell → bắt đầu drag là toàn bộ cell cập nhật | `HistoryView.swift:733,746` |
| Các lớp lách SwiftUI `Table`: `NSEvent` monitor cho right-click, đổi `dataSource` để thay drag preview, tự khôi phục độ rộng cột, chặn click sau drag, poll chuột 50ms | `HistoryTableScrollCoordinator.swift`, `HistoryDragPreviewDataSource.swift`, `HistoryView.swift:2572-2648` |

## 2. Mục tiêu

1. Click / phím ↑↓ chọn commit **không** làm table đánh giá lại rows; chỉ detail panel cập nhật.
2. Scroll không chạy code per-cell của SwiftUI; phân trang dựa trên viewport, không dựa trên `onAppear`.
3. Thay đổi bên ngoài (AppState, MainWindow re-render, closure mới) không reload table.
4. Bỏ toàn bộ lớp lách SwiftUI `Table` bằng cách dùng `NSTableView` trực tiếp.
5. Tách `HistoryView` thành các đơn vị có trách nhiệm rõ: list model, detail model, action controller, table, view.

## 3. Không thay đổi (giữ nguyên hành vi)

- **UI:** 5 cột Graph / Message / Author / Date / Commit; bordered, alternating rows, control size small, row height 24pt; ref badge trong message cell (tối đa 3 + "+N"); split dọc `HistoryMainSplit` (list trên, detail dưới); split ngang `HistoryDetailSplit` trong detail; header commit, popover thông tin commit, chỉ báo "Loading branch history…", empty state, "Loading older commits…" row.
- **Các view con dùng lại nguyên trạng:** `BranchFilterBar`, `CommitFileListView`, `DiffView`, `CommitInfoPopoverView`, `CommitFilePreviewSheet`, `CommitPatchReviewSheet`, `SquashCommitsSheet`, `RefLabel` (cho header detail), `CommitDragPreview`, `EmptyStateView`, `PersistentVSplit` / `PersistentHSplit`.
- **Logic dùng lại:** `CommitGraphGenerator` (+ incremental/append), `CommitGraphRowGeometryCache`, `HistoryCommitSelection`, `HistoryPagingState`, `HistoryCheckoutPolicy`, `BoundedMemoryCache` (capacity 3), toàn bộ API `GitStatusService` đang gọi, `CommitPatchController`, `GitDragPayload` / `GitDragPayloadStore`.
- **Context menu:** cùng danh sách mục, thứ tự, divider, icon, điều kiện enable (single / multi / cherry-pick không merge / squash theo `canSquashCommits`), submenu Custom Actions, Copy Hash(es) / Message(s).
- **Double-click / Return:** `handleCommitDoubleClick` — có branch ref thì `onRequestCheckout`, không thì xác nhận checkout detached (kèm kiểm tra uncommitted changes).
- **Right-click trên row chưa chọn:** chọn row đó (bỏ selection cũ) rồi mới mở menu. Right-click trên row đã chọn: giữ selection, menu áp dụng cho toàn bộ selection.
- **Drag:** payload `GitDragPayload.commits` theo `draggedCommits(startingAt:commits:selection:)`, preview `CommitDragPreview` một ảnh kèm badge số lượng, row đang kéo mờ 0.4.
- **Data flow:** phân trang 2 chiều (cửa sổ `startIndex` + `loadedCount`), cache 3 snapshot theo `historyLoadKey`, refresh qua `.repositoryDidChange` / `.repositoryLocalStateDidRefresh` / `.advancedClearSessionCaches` với giữ selection và viewport, search debounce, "only this branch" so với base branch, setting `advanced.historyLoadSize`, chọn tip của `selectedBranch` khi filter là `.all`.
- **Undo:** `registerHeadChangingUndo` và các `perform*` giữ nguyên logic, chỉ chuyển chỗ.

## 4. Không nằm trong phạm vi

- Không đổi git query, thuật toán graph, giao diện, text của sheet / menu.
- Không đổi Reflog, Sidebar, các drop target của drag.
- Không đổi định dạng `GitDragPayload`.

## 5. Kiến trúc mới

```
MainWindowView
└── HistoryScreen (SwiftUI, body mỏng – chỉ ghép các phần)
    ├── BranchFilterBar                         (giữ nguyên)
    ├── PersistentVSplit "HistoryMainSplit"
    │   ├── HistoryCommitTable                  (NSViewRepresentable → NSScrollView + HistoryNSTableView)
    │   │     └── HistoryCommitTableController  (dataSource / delegate / NSMenuDelegate / drag)
    │   └── HistoryCommitDetailView             (chỉ observe HistoryCommitDetailModel)
    └── .historyActionPresentations(controller) (sheet / alert, chỉ observe HistoryCommitActionController)

HistoryListModel            @Observable @MainActor – commits, graph, paging, cache, selection, load
HistoryCommitDetailModel    @Observable @MainActor – files, line counts, diff, full message, patch
HistoryCommitActionController @Observable @MainActor – pendingCommit, sheet hiện tại, perform*
HistoryCommitContextMenu    SwiftUI View (nội dung menu), dựng lazily qua NSHostingMenu
```

### 5.1 Vị trí file

| File mới | Thư mục |
|---|---|
| `HistoryListModel.swift` | `macgit/ViewModels/` |
| `HistoryCommitDetailModel.swift` | `macgit/ViewModels/` |
| `HistoryCommitActionController.swift` | `macgit/ViewModels/` |
| `HistoryLoadPolicy.swift` (các hàm static thuần) | `macgit/Views/History/` |
| `HistoryScreen.swift` | `macgit/Views/History/` |
| `HistoryCommitTable.swift` (representable + `HistoryNSTableView`) | `macgit/Views/History/` |
| `HistoryCommitTableController.swift` | `macgit/Views/History/` |
| `HistoryCommitTableCells.swift` (graph / message / text cell) | `macgit/Views/History/` |
| `HistoryRefBadgeView.swift` | `macgit/Views/History/` |
| `CommitGraphRowRenderer.swift` (vẽ CoreGraphics dùng chung) | `macgit/Views/History/` |
| `HistoryCommitDetailView.swift` | `macgit/Views/History/` |
| `HistoryCommitContextMenu.swift` | `macgit/Views/History/` |
| `HistoryActionSheets.swift` (tag / branch / reset / merge / rebase / checkout sheet + modifier) | `macgit/Views/History/` |

File xoá sau khi chuyển xong: `HistoryView.swift`, `HistoryTableScrollCoordinator.swift`, `HistoryDragPreviewDataSource.swift`, `HistoryCommitMessageCell.swift`, `HistoryTableRow.swift`, `BranchGraphRowCanvas.swift` (nếu không còn nơi dùng).

### 5.2 `HistoryListModel`

Trách nhiệm: nguồn dữ liệu duy nhất của danh sách.

```swift
@Observable @MainActor
final class HistoryListModel {
    // Inputs (set bởi HistoryScreen)
    var repositoryURL: URL
    var branchFilter: HistoryBranchFilter
    var onlyThisBranch: Bool
    var baseBranch: String?
    var searchText: String          // raw; debounce nội bộ → activeSearchQuery
    var selectedBranch: String?

    // Outputs
    private(set) var rows: HistoryRowsSnapshot       // commits + graphModel + hasMore + version + change kind
    private(set) var selection: HistoryCommitSelection
    private(set) var selectedCommit: Commit?
    private(set) var headHash: String?
    private(set) var isInitialLoading: Bool
    private(set) var isRefreshing: Bool              // chỉ báo sau 150ms như hiện tại
    private(set) var scrollRequest: HistoryScrollRequest?   // (hash, token) – table tiêu thụ một lần
    private(set) var dragActiveHashes: Set<String>
    var errorMessage: String?

    func loadKeyDidChange() async                    // = .task(id: loadKey) hiện tại
    func refresh(preservingSelectionAndScroll: Bool) async
    func viewportDidChange(visibleRows: Range<Int>)  // thay handleHistoryCommitCellAppearance
    func applyNativeSelection(orderedHashes: [String], previous: Set<String>)
    func selectForContextClick(hash: String)
    func selectBranchTip(_ branch: String)
    func clearCaches()
    var selectedHashesInDisplayOrder: [String] { get }
}
```

- `HistoryRowsSnapshot` là struct bất biến gồm `commits: [Commit]`, `graphModel: CommitGraphModel`, `hasMore: Bool`, `version: Int`, `change: Change` với `enum Change { case reload, appended(Range<Int>), prepended(count: Int) }`. `version` tăng mỗi lần gán. Table chỉ phản ứng khi `version` đổi.
- Kèm `hashIndex: [String: Int]` dựng một lần mỗi snapshot để bỏ các phép `commits.map(\.hash)` / `firstIndex` lặp lại.
- Logic `loadHistory`, `applyCachedSnapshot`, `loadOlderHistoryIfNeeded`, `loadNewerHistoryIfNeeded`, `historyPage`, `restoreSelectionIfTableClearsAfterReload` (không còn cần – xem 5.5), `scheduleHistorySearchDebounce`, refresh indicator chuyển nguyên sang đây. `appState.historyBranchFilter` thay bằng thuộc tính `branchFilter`.
- Viewport anchor khi refresh: model không biết về `NSTableView`. Snapshot với `change == .reload` mang cờ `preserveViewport: Bool`; table controller tự chụp anchor trước khi reload và khôi phục sau.

### 5.3 `HistoryCommitDetailModel`

```swift
@Observable @MainActor
final class HistoryCommitDetailModel {
    private(set) var commit: Commit?
    private(set) var fileChanges: [CommitFileChange]
    private(set) var lineCounts: [String: FileLineChangeCount]
    var selectedFile: CommitFileChange?            // didSet → loadDiff
    private(set) var diffHunks: [DiffHunk]
    private(set) var diffCommitHash: String?
    private(set) var diffFilePath: String?
    private(set) var fullMessage: String?
    private(set) var isLoadingFullMessage: Bool
    var showingCommitInfo: Bool
    var fullFilePreview: CommitFilePreviewRequest?
    let patchController: CommitPatchController
    private(set) var patchReasons / patchEligibilityLoaded / patchEligibilityError

    func show(_ commit: Commit?)                    // header cập nhật ngay; file list load sau debounce
    func resumeIfCancelled()                        // thay logic onAppear hiện tại
    func cancelLoads()                              // onDisappear
    func loadFullMessage()
    func patchDisabledReason(for files: [CommitFileChange]) -> String?
}
```

- `show(_:)` cập nhật `commit` ngay (header đổi tức thì), huỷ task cũ, đợi **80ms** rồi mới gọi `loadFileChanges`. Phím ↑↓ giữ liên tục chỉ tải commit cuối cùng.
- Gán state theo lô: kết quả file list + line counts gán trong một lần cập nhật để detail view chỉ render một lượt.
- `HistoryScreen` nối: `listModel.selectedCommit` đổi → `detailModel.show(...)` (qua `.onChange(of: listModel.selectedCommit?.hash)`).

### 5.4 `HistoryCommitActionController`

```swift
@Observable @MainActor
final class HistoryCommitActionController {
    enum Presentation: Identifiable { case checkout, reset, tag, branch, merge, rebase, squash([Commit], String) }
    var presentation: Presentation?
    var showingRevertConfirmation: Bool
    var pendingCommit: Commit?
    // inputs của sheet: tagName, branchName, checkoutNewBranch, resetMode, currentBranchName,
    // mergeCommitImmediately, mergeIncludeMessages, discardLocalChanges, hasUncommittedChanges
    var errorMessage: String?; var showingError: Bool

    struct Dependencies {
        let repositoryURL: URL
        let undoManager: GitUndoManager?
        let syncState: SyncState?
        let runOperation: RepositoryOperationRunner
        let requestCheckout: (String, Bool) -> Void
        let requestExplain: (Commit) -> Void
        let requestBrowseRevision: (Commit) -> Void
        let runCustomAction: (UUID, [String]) -> Void
    }
    var dependencies: Dependencies     // cập nhật mỗi lần HistoryScreen dựng lại; không gây render

    // Mục menu
    func browseRevision(_:), requestCheckoutCommit(_:), cherryPick(_:), explain(_:), requestMerge(_:),
         requestRebase(_:), requestSquash(_:), requestTag(_:), requestBranch(_:), requestReset(_:),
         requestRevert(_:), copyHashes(_:), copyMessages(_:)
    func handleDoubleClick(_ commit: Commit)
    // perform* (chuyển nguyên từ HistoryView)
}
```

- Một enum `Presentation` thay 7 cờ `showingXxx`, khớp cách `replacingSheet(item:)` đang dùng.
- `dependencies` lưu closure mới nhất nhưng không phải thuộc tính observe (đánh dấu `@ObservationIgnored`).

### 5.5 Table: `HistoryCommitTable` + `HistoryCommitTableController`

**Dựng bảng (một lần trong `makeNSView`):**
- `HistoryNSTableView: NSTableView`, `style = .fullWidth`, `gridStyleMask = [.solidVerticalGridLineMask]` (khớp `.bordered`), `usesAlternatingRowBackgroundColors = true`, `rowHeight = 24`, `intercellSpacing` khớp hiện tại, `allowsMultipleSelection = true`, `allowsColumnReordering = true`, `columnAutoresizingStyle = .noColumnAutoresizing` (như hiện tại).
- Cột (identifier = customization ID cũ): `graph` (min 60, w 200), `message` (min 120, w 400), `author` (min 140, w 180), `date` (min 100, w 140), `commit` (min 72, w 80). `graph`/`message` không ẩn được, không cho kéo đổi chỗ (chặn trong `tableView(_:shouldReorderColumn:toColumn:)`). Header có menu ẩn/hiện `author` / `date` / `commit`.
- Lưu cột: `autosaveName = "HistoryCommitTable"`, `autosaveTableColumns = true`. Lần đầu (chưa có autosave) dựng độ rộng theo tỉ lệ cũ trong `history.tableColumnRatios` nếu có, để người dùng không mất layout.
- `menu = NSMenu()` với `delegate = controller` (context menu), `doubleAction` + `target`.
- `registerForDraggedTypes` không cần (bảng không nhận drop). `setDraggingSourceOperationMask(.copy, forLocal: true/false)`.

**`updateNSView` – quy tắc invalidation (cốt lõi của spec):**
1. Luôn cập nhật `controller.listModel`, `controller.actions`, `controller.textScale` (gán tham chiếu, không reload).
2. Nếu `rows.version` khác version controller đã áp dụng:
   - `.appended(range)` → `insertRows(at:)` cho range, không đụng viewport.
   - `.prepended(count)` → `insertRows(at: 0..<count)` rồi cộng `count * rowHeight` vào `clipView.bounds.origin.y` (row height cố định nên anchor chính xác).
   - `.reload` → nếu `preserveViewport` thì chụp anchor (hash row đầu tiên nhìn thấy + offset) → `reloadData()` → khôi phục anchor theo `hashIndex`.
   - Loading row ("Loading older commits…") là row cuối khi `hasMore`; tính trong `numberOfRows`.
3. Nếu selection của model khác selection trên bảng → `selectRowIndexes(_:byExtendingSelection:false)` trong khối `isApplyingModelSelection = true` để không phát ngược về model. Hash ngoài cửa sổ hiện tại bị bỏ qua (giữ hành vi "pinned detail").
4. Nếu `scrollRequest.token` mới → cuộn để row đó nằm giữa (logic hiện ở `scrollToRowWhenReady`), xong gọi `listModel.consumeScrollRequest(token)`.
5. Nếu `dragActiveHashes` đổi → chỉ cập nhật `alphaValue` của các row view đang hiển thị thuộc tập cũ ∪ mới.
6. Nếu `textScale` đổi → `reloadData()` (hiếm).

Không có điều kiện nào khác dẫn tới reload. Detail, sheet, AppState, closure mới đều không chạm vào bảng.

**Cells (AppKit thuần, tái sử dụng qua `makeView(withIdentifier:owner:)`):**
- `HistoryGraphCellView`: `draw(_:)` gọi `CommitGraphRowRenderer.draw(geometry:rowIndex:in:dotBackground:)`. Geometry lấy từ `graphModel.rowGeometryCache.geometry(for:rowIndex:)`. Dot background: `selectedContentBackgroundColor` khi `backgroundStyle == .emphasized`, ngược lại theo `alternatingContentBackgroundColors[row % n]` — giống `BranchGraphRowCanvas.dotBackground`. Vẽ tràn 4pt trên/dưới như hiện tại để line liền mạch giữa các row.
- `HistoryMessageCellView`: `NSStackView` ngang gồm tối đa 3 `HistoryRefBadgeView` + label "+N" (tooltip là các ref còn lại) + `NSTextField` (1 dòng, truncate tail, tooltip = message, "<empty message>" khi rỗng). Reuse: cập nhật badge bằng cách tái dùng view có sẵn, không tạo mới mỗi lần.
- `HistoryRefBadgeView`: bản AppKit của `RefLabel` – cùng `displayText`, icon `tag` / `arrow.triangle.branch`, màu (tag tím 15%, graph color 20%, accent 15%), capsule, font 11 semibold × textScale; khi row được chọn (`backgroundStyle == .emphasized`) dùng màu primary + nền primary 12%. Logic `displayText` / `isTag` / màu tách ra `RefLabelStyle` dùng chung cho cả `RefLabel` SwiftUI và bản AppKit.
- `HistoryTextCellView` cho Author (`"name <email>"`, secondary, tooltip), Date (formatter dùng chung, `.dateTime.hour().minute().day().month(.abbreviated).year()`, monospaced digit, secondary), Commit (`shortHash`, monospaced, tertiary, tooltip = full hash). Font callout × textScale.
- Loading row: một cell view riêng span cột message (`ProgressIndicator` small + "Loading older commits…").

**Phân trang:**
- Controller quan sát `NSView.boundsDidChangeNotification` của clip view (đã có `postsBoundsChangedNotifications`). Mỗi lần đổi → `rows(in: visibleRect)` → nếu range khác lần trước thì `listModel.viewportDidChange(visibleRows:)`. Ngưỡng prefetch giữ nguyên: `max(pageSize, visible.count * 3)`.
- Cũng gọi một lần sau mỗi lần áp snapshot mới (thay cho `onAppear` của loading row).

**Selection:**
- `tableViewSelectionDidChange`: nếu `isApplyingModelSelection` thì bỏ qua; ngược lại map `selectedRowIndexes` → hash theo thứ tự hiển thị (bỏ loading row) → `listModel.applyNativeSelection(orderedHashes:previous:)`. Model dùng `primaryHashForTableSelection` như hiện tại.
- Model đẩy selection cho MainWindow (custom actions) — xem 5.8.

**Context menu (right-click):**
- `menuNeedsUpdate(_ menu:)`:
  1. `row = tableView.clickedRow`; nếu `row < 0` hoặc là loading row → menu rỗng.
  2. Nếu `row` không thuộc `selectedRowIndexes` → `selectRowIndexes([row], byExtendingSelection: false)` (đi qua đường selection bình thường → model cập nhật).
  3. `hashes = selection hiện tại theo thứ tự hiển thị`.
  4. Thay item của `menu` bằng item của `NSHostingMenu(rootView: HistoryCommitContextMenu(...))` — tức dùng lại cách đang làm ở `HistoryView.swift:252`.
- `HistoryCommitContextMenu` là `View` struct nhận `contextCommits`, `primaryCommit`, `headHash`, `actions`, `customActionStore`, `repositoryURL` — chuyển nguyên `commitContextMenu(for:)` sang, thay các thao tác state bằng lời gọi `actions.xxx`.
- Bỏ: `NSEvent` context-click monitor, `isContextClick(onRows:)`, chặn selection rỗng trong binding.

**Double-click / Return:**
- `doubleAction` → `clickedRow` hợp lệ → `actions.handleDoubleClick(commit)`. Return / Enter trong `HistoryNSTableView.keyDown` → primary commit của selection → cùng hàm.
- Bỏ: `suppressedCommitClickHash` và các task liên quan (AppKit không phát double-click sau drag).

**Drag:**
- `HistoryNSTableView.mouseDown` ghi `dragOriginRow = row(at:)` trước khi gọi `super`.
- `tableView(_:pasteboardWriterForRow:)`: chỉ trả writer cho `dragOriginRow` (các row khác trả `nil` để chỉ có một dragging item). Writer là `NSPasteboardItem` với data `GitDragPayload.encodeTransferData(payload)` cho type `UTType.macgitGitDragPayload.identifier`. Payload tính bằng `draggedCommits(startingAt:commits:selection:)` như `makeCommitDragPayload`. Đồng thời `GitDragPayloadStore.set(payload)`.
- `draggingSession(_:willBeginAt:forRowIndexes:)`: render `CommitDragPreview` bằng `ImageRenderer` (chuyển từ `HistoryDragPreviewDataSource.prepare`) và đặt làm dragging frame, `draggingFormation = .none`; `listModel.setDragActive(hashes)`.
- `draggingSession(_:endedAt:operation:)`: `listModel.setDragActive([])`. Không xoá `GitDragPayloadStore` (giữ như `finishCommitDrag(clearsPayload: false)`).
- Bỏ: `.draggable` per row, poll `pressedMouseButtons`, swap `dataSource`.

**Focus:** khi `selectedBranch` đổi và filter là `.all`, model phát `scrollRequest` kèm `focus: true`; controller gọi `window.makeFirstResponder(tableView)` sau khi cuộn.

### 5.6 `HistoryCommitDetailView`

- Nhận `detailModel`, `repositoryURL`, `textScale`. Chứa `commitInfoHeader`, thanh "Checking and merging selected changes…", `PersistentHSplit("HistoryDetailSplit")` với `CommitFileListView` + diff viewer — chuyển nguyên từ `HistoryView.swift:820-1043`.
- Vì chỉ observe `detailModel`, thay đổi diff / file list không chạm list.
- Sheet `CommitFilePreviewSheet` và `CommitPatchReviewSheet` + alert "Selected changes" gắn ở view này (chúng thuộc detail).

### 5.7 `HistoryScreen`

```swift
struct HistoryScreen: View {
    let repositoryURL: URL
    let selectedBranch: String?
    @Binding var branchFilter: HistoryBranchFilter
    @Binding var includeRemotes: Bool
    let dependencies: HistoryCommitActionController.Dependencies
    let selectionSink: HistoryCommitSelectionSink
    @State private var listModel: HistoryListModel
    @State private var detailModel: HistoryCommitDetailModel
    @State private var actions: HistoryCommitActionController
    @State private var onlyThisBranch = false
    @State private var baseBranch: String?
    @State private var searchText = ""
    @AppStorage("advanced.historyLoadSize") private var historyLoadSizeRaw = 120
    @EnvironmentObject private var customActionStore: CustomActionStore
}
```

- Không dùng `@EnvironmentObject AppState`. MainWindow truyền `$appState.historyBranchFilter` và `$appState.historyIncludeRemotes`.
- `body` chỉ: `BranchFilterBar` + trạng thái loading/empty + `PersistentVSplit(top: HistoryCommitTable, bottom: HistoryCommitDetailView)` + overlay refresh + `.historyActionPresentations(actions)` + alert lỗi.
- `.task(id: loadKey)`, `.onReceive` 3 notification, `.onChange` của filter/search/load size/`selectedBranch` → gọi method của `listModel`.
- `.onChange(of: listModel.selectedCommit?.hash)` → `detailModel.show(listModel.selectedCommit)`.
- `.onChange(of: listModel.selectedHashesInDisplayOrder)` → `selectionSink.update(...)`.
- `.onAppear` → `detailModel.resumeIfCancelled()`; `.onDisappear` → huỷ task của cả 2 model.
- Mỗi lần body chạy chỉ cập nhật `actions.dependencies` (`@ObservationIgnored`), không gây thêm lượt render.

### 5.8 Tích hợp MainWindow

- Thay `HistoryView(...)` ở `MainWindowView.swift:1376` bằng `HistoryScreen(...)` với binding AppState và `Dependencies` gom các closure hiện có.
- Custom actions: thay closure `onCustomActionSelectionChanged` bằng `HistoryCommitSelectionSink` (một `@Observable` class nhỏ do MainWindow giữ trong `@State`, có `commitHashes: [String]`). `customActionCommandState` đọc `sink.commitHashes` thay cho `customActionCommitHashes`. Sink chỉ gán khi giá trị thực sự khác (`guard new != old`). Nhờ body của `HistoryScreen` rẻ và table không reload, lượt render của MainWindow (nếu có) không còn kéo theo đánh giá lại rows.
- `onRunCustomAction` giữ nguyên, nằm trong `Dependencies.runCustomAction`.

## 6. Rủi ro & cách xử lý

| Rủi ro | Xử lý |
|---|---|
| Giao diện AppKit lệch với SwiftUI `Table` (padding, font, màu selection) | Dùng cùng metric hiện tại: row 24pt, control size small, font callout × textScale, màu secondary / tertiary qua `NSColor.secondaryLabelColor` / `tertiaryLabelColor` |
| Ref badge AppKit lệch `RefLabel` | Tách `RefLabelStyle` dùng chung để màu / text / icon chỉ có một nguồn |
| Mất layout cột đã lưu | Migration một lần từ `history.tableColumnRatios` khi autosave chưa có |
| Drop target đang kỳ vọng nhiều item | Payload đã chứa toàn bộ commit. Drop commit lên sidebar đọc `GitDragPayloadStore.currentPayload()` trước (`SidebarView+DragDrop.swift`); các `dropDestination(for: GitDragPayload.self)` khác chỉ xử lý stash. Khi làm Task 6, rà lại các drop handler nhận commit để chắc chắn chúng không phụ thuộc số lượng item |
| Hàm static đang được test tham chiếu `HistoryView.xxx` | Chuyển sang `HistoryLoadPolicy` và cập nhật tham chiếu trong `macgitTests` cho compile được |
