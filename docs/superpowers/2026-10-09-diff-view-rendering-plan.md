# Diff View Rendering Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `DiffView` scroll smoothly on files with huge bulk changes and on lines with hundreds of thousands of characters, by replacing per-row SwiftUI hosting views with one drawing canvas per visible hunk and moving all text work into content-keyed, off-main caches.

**Spec:** `docs/superpowers/specs/2026-10-09-diff-view-rendering-design.md`. Every task is written against the spec's **§4 Behavior contract** and **§5 Component design**. Use the old code for lookup only.

**Architecture:** Keep the outer `NSScrollView`, `DiffHunkGeometry`, per-hunk `DiffNativeHunkView` recycling and per-hunk `DiffHunkScrollView`. Inside each hunk, a viewport-sized `DiffHunkCanvasView` draws rows from cached `CTLine`s. Shared stores (`DiffTextLayoutStore`, `DiffLongLineStore`, `DiffHighlightStore`, `DiffWidthIndex`) are owned by the `DiffNativeTable.Coordinator`. Actions and menus are driven by pure models shared between the SwiftUI header and the AppKit row menu.

**Tech Stack:** Swift, AppKit (`NSView` drawing, `NSMenu`), CoreText, SwiftUI (hunk header only), XCTest, `os.signpost`.

**Conventions:**
- Branch: `codex/diff-canvas-renderer`.
- New Swift files start with `// SPDX-License-Identifier: AGPL-3.0-or-later`. New diff files go in `macgit/Views/Common/Diff/` (synchronized folders: no `.xcodeproj` edits).
- New code lives alongside the old path until Task 12 switches `DiffView`; Task 14 deletes the old path. The app must build at the end of **every** task.
- Build: `rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
- Test (narrow): `rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/<TestClass> test`
- Run builds and tests sequentially. Do not commit, stash or push unless the user asks; the “Checkpoint” step marks a good commit point.

---

### Task 0: Fixtures and instrumentation

**Files:**
- Create: `macgit/Views/Common/Diff/DiffSignpost.swift`
- Create: `macgitTests/Support/DiffFixtures.swift`
- Create: `scripts/make-diff-perf-fixture.sh`

- [ ] **Step 1: Signposts and debug counters**

```swift
// SPDX-License-Identifier: AGPL-3.0-or-later
import os

nonisolated enum DiffSignpost {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "macgit", category: "DiffView")

    @inline(__always)
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}

#if DEBUG
@MainActor
enum DiffRenderStats {
    static var headerHostAssignments = 0
    static var canvasDraws = 0
    static var lineBuilds = 0
    static var longLinePreparations = 0
    static func reset() { headerHostAssignments = 0; canvasDraws = 0; lineBuilds = 0; longLinePreparations = 0 }
}
#endif
```

- [ ] **Step 2: Test fixtures** — `DiffFixtures` with `hunk(lines:lineLength:type:)`, `hunks(count:linesEach:)`, `longASCIILine(length:)`, `longCJKLine(length:)`, `crlfLine(_:)`, `tabbedLine(_:)`. All built through `DiffHunk(header:lines:)`.
- [ ] **Step 3: Manual fixture script** — `scripts/make-diff-perf-fixture.sh <dir>`: `git init`, commit a baseline, then write (uncommitted) a file with 200 000 changed lines, a file with 2 000 small hunks (change every 50th line of a 100 000-line file), `minified.js` with one 500 000-char ASCII line, `cjk.txt` with one 200 000-char CJK line, `crlf.txt` with CRLF endings, `tabs.go` with tab indentation. Print the repo path.
- [ ] **Step 4: Baseline** — run the script, open the repo in a Release build, record Instruments (Time Profiler + Animation Hitches + `DiffView` signposts are not there yet, so Time Profiler only) while scrolling each file. Save the numbers in the PR description as “before”.
- [ ] **Step 5:** Build. Checkpoint.

### Task 1: Stable identity and header counts

**Files:**
- Modify: `macgit/Services/GitDiffModels.swift`
- Create: `macgitTests/DiffIdentityTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
final class DiffIdentityTests: XCTestCase {
    private func parse() -> [DiffHunk] {
        DiffParser.parse("""
        @@ -1,3 +1,3 @@
         a
        -b
        +c
        @@ -10,2 +10,3 @@
         x
        +y
        """)
    }

    func testReparsingSameDiffYieldsSameIDs() {
        let first = parse(), second = parse()
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.flatMap(\.lines).map(\.id), second.flatMap(\.lines).map(\.id))
    }

    func testIdenticalTextOnDifferentRowsHasDistinctIDs() {
        let hunk = DiffHunk(header: "@@ -1,2 +1,2 @@", lines: [
            DiffLine(oldLineNumber: 1, newLineNumber: 1, text: "", type: .context),
            DiffLine(oldLineNumber: 2, newLineNumber: 2, text: "", type: .context),
        ])
        XCTAssertNotEqual(hunk.lines[0].id, hunk.lines[1].id)
    }

    func testEditedLineChangesOnlyItsOwnID() {
        let a = DiffHunk(header: "@@ -1,2 +1,2 @@", lines: [
            DiffLine(oldLineNumber: nil, newLineNumber: 1, text: "one", type: .added),
            DiffLine(oldLineNumber: nil, newLineNumber: 2, text: "two", type: .added)])
        let b = DiffHunk(header: "@@ -1,2 +1,2 @@", lines: [
            DiffLine(oldLineNumber: nil, newLineNumber: 1, text: "one", type: .added),
            DiffLine(oldLineNumber: nil, newLineNumber: 2, text: "TWO", type: .added)])
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.lines[0].id, b.lines[0].id)
        XCTAssertNotEqual(a.lines[1].id, b.lines[1].id)
        XCTAssertNotEqual(a.lines[1].contentKey, b.lines[1].contentKey)
    }

    func testHeaderCounts() {
        let hunk = parse()[0]
        XCTAssertEqual(hunk.addedCount, 1)
        XCTAssertEqual(hunk.removedCount, 1)
    }
}
```

- [ ] **Step 2:** Run `DiffIdentityTests` → FAIL (`contentKey`, `addedCount` missing; ids differ).
- [ ] **Step 3: Implement** (spec §5.1)

```swift
nonisolated enum DiffIdentity {
    static func uuid(_ high: Int, _ low: Int) -> UUID {
        let h = UInt64(bitPattern: Int64(high)), l = UInt64(bitPattern: Int64(low))
        func b(_ v: UInt64, _ i: Int) -> UInt8 { UInt8(truncatingIfNeeded: v >> (8 * i)) }
        return UUID(uuid: (b(h,0), b(h,1), b(h,2), b(h,3), b(h,4), b(h,5), b(h,6), b(h,7),
                           b(l,0), b(l,1), b(l,2), b(l,3), b(l,4), b(l,5), b(l,6), b(l,7)))
    }
}
```

  - `DiffLineType: Hashable`.
  - `DiffLine`: `fileprivate(set) var id = UUID()`, `let contentKey: Int` computed in the existing initializer (`text.hashValue`).
  - `DiffHunk`: `let id: UUID` (no default); in `init(header:lines:)` compute `hunkSeed = Hasher.combine(header, lines.count)`, set `id = DiffIdentity.uuid(hunkSeed, 0x48554e4b)`, copy `lines` into a `var`, re-stamp each `id` with `DiffIdentity.uuid(hash(hunkSeed, index, type, old, new), contentKey)`, and compute `addedCount`/`removedCount` in the existing run loop.
- [ ] **Step 4:** Run `DiffIdentityTests`, `DiffPatchBuilderTests`, `CommitPatchIntegrationTests` → PASS.
- [ ] **Step 5:** Build. Checkpoint.

### Task 2: `SyntaxTokenizer` (off-main tokenization)

**Files:**
- Create: `macgit/Services/SyntaxTokenizer.swift`
- Modify: `macgit/Services/SyntaxHighlighter.swift`
- Create: `macgitTests/SyntaxTokenizerTests.swift`

- [ ] **Step 1: Write failing parity test** — for each identifier in `["swift","ts","js","cs","py","go","rs","json","css","sh","toml","makefile","unknown"]`, tokenize a short representative snippet with `SyntaxTokenizer.tokens(in:language:)` and compare `(range, type)` pairs to what the current private `mergedTokenRanges` produces. Before extraction, expose the old result with a temporary `@testable` `internal func _legacyTokenRanges(in:)` on `SyntaxHighlighter`; delete it in Step 4.
- [ ] **Step 2:** Run → FAIL (type missing).
- [ ] **Step 3: Implement**
  - Move `TokenType` → `nonisolated enum SyntaxTokenType: Sendable { keyword, string, comment, number, type, attribute, normal }`; `nonisolated struct SyntaxToken: Sendable, Equatable { let range: NSRange; let type: SyntaxTokenType }`.
  - Move `keywordPattern`, `rules(for:)` and `TokenRules` into `nonisolated enum SyntaxTokenizer`; protect the rules cache with `OSAllocatedUnfairLock<[String: TokenRules]>` (`TokenRules` is `@unchecked Sendable`; `NSRegularExpression` is immutable and safe to share).
  - `static func tokens(in text: String, language: String) -> [SyntaxToken]` = old `mergedTokenRanges`.
  - Mark `SyntaxHighlighter.syntaxIdentifier(forLanguage:)` and `syntaxIdentifier(forFilePath:)` `nonisolated`.
  - `SyntaxHighlighter.attributedString`/`nsAttributedString` call the tokenizer; add `static func color(for: SyntaxTokenType) -> NSColor?` (old `tokenColor`).
- [ ] **Step 4:** Run `SyntaxTokenizerTests` → PASS; remove the temporary legacy hook and its comparison (keep the expected token tables inline instead).
- [ ] **Step 5:** Build. Checkpoint.

### Task 3: `DiffTextMetrics` and `DiffGenerationalCache`

**Files:**
- Create: `macgit/Views/Common/Diff/DiffTextMetrics.swift`
- Create: `macgit/Views/Common/Diff/DiffGenerationalCache.swift`
- Create: `macgitTests/DiffTextMetricsTests.swift`, `macgitTests/DiffGenerationalCacheTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
final class DiffTextMetricsTests: XCTestCase {
    func testASCIIColumnsExpandTabsToFourColumnStops() {
        XCTAssertEqual(DiffTextMetrics.asciiColumns("abc"), 3)
        XCTAssertEqual(DiffTextMetrics.asciiColumns("\tx"), 5)
        XCTAssertEqual(DiffTextMetrics.asciiColumns("ab\tx"), 5)
        XCTAssertEqual(DiffTextMetrics.asciiColumns("abcd\tx"), 9)
    }
    func testTrailingCarriageReturnIsIgnored() {
        XCTAssertEqual(DiffTextMetrics.asciiColumns("abc\r"), 3)
    }
    func testNonASCIIReturnsNil() {
        XCTAssertNil(DiffTextMetrics.asciiColumns("café"))
        XCTAssertNil(DiffTextMetrics.asciiColumns("中文"))
        XCTAssertNil(DiffTextMetrics.asciiColumns("a\u{0007}b"))
    }
    func testExpandTabsMatchesColumns() {
        let text = "a\tbc\t\td\r"
        XCTAssertEqual(DiffTextMetrics.expandTabs(text).count, DiffTextMetrics.asciiColumns(text))
    }
    func testHalfMillionCharacterLineIsLinear() {
        let line = String(repeating: "x", count: 500_000)
        measure { _ = DiffTextMetrics.asciiColumns(line) }
    }
}

final class DiffGenerationalCacheTests: XCTestCase {
    func testBoundedAndPromotesRecentlyRead() {
        var cache = DiffGenerationalCache<Int, Int>(capacity: 4)
        for i in 0..<4 { cache.insert(i, for: i) }
        XCTAssertEqual(cache.value(for: 0), 0)          // promoted
        for i in 4..<6 { cache.insert(i, for: i) }
        XCTAssertLessThanOrEqual(cache.count, 4)
        XCTAssertEqual(cache.value(for: 0), 0)
    }
}
```

- [ ] **Step 2:** Run both → FAIL.
- [ ] **Step 3: Implement**

```swift
nonisolated enum DiffTextMetrics {
    static let tabWidth = 4

    static func asciiColumns(_ text: String) -> Int? {
        var columns = 0
        var utf8 = Substring(text).utf8
        if utf8.last == 0x0D { utf8 = utf8.dropLast() }
        for byte in utf8 {
            switch byte {
            case 0x09: columns += tabWidth - columns % tabWidth
            case 0x20...0x7E: columns += 1
            default: return nil
            }
        }
        return columns
    }

    /// Precondition: `asciiColumns(text) != nil`.
    static func expandTabs(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count)
        for byte in text.utf8 where byte != 0x0D {
            if byte == 0x09 {
                out.append(contentsOf: repeatElement(0x20, count: tabWidth - out.count % tabWidth))
            } else { out.append(byte) }
        }
        return out
    }

    /// Display form for short non-ASCII lines (tabs expanded by Character columns, trailing CR dropped).
    static func displayString(_ text: String) -> String { /* same rule over Characters */ }
}
```

  `DiffGenerationalCache<Key: Hashable, Value>` (spec §5.9): `current`, `previous` dictionaries; `value(for:)` checks `current`, else moves from `previous` into `current`; `insert` writes `current` and, when `current.count >= capacity / 2`, sets `previous = current`, `current = [:]`; `count = current.count + previous.count`; `removeAll()`.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Build. Checkpoint.

### Task 4: `DiffRenderContext` and `DiffTextLayoutStore`

**Files:**
- Create: `macgit/Views/Common/Diff/DiffRenderContext.swift`
- Create: `macgit/Views/Common/Diff/DiffTextLayoutStore.swift`
- Create: `macgitTests/DiffTextLayoutStoreTests.swift`

- [ ] **Step 1: `DiffRenderContext`** (`@MainActor final class`, spec §5.2). `update(textScale:syntaxHighlighting:fileExtension:appearance:) -> Bool` returns whether anything changed and bumps `styleVersion`. Resolve every color with `appearance.performAsCurrentDrawingAppearance { NSColor.x.cgColor }`: backgrounds (accent 0.12, `systemGreen` 0.08, `systemRed` 0.08, `systemPurple` 0.10), line colors (added `0.12/0.55/0.18`, removed `0.75/0.18/0.18`, header `secondaryLabelColor`, conflict `systemPurple`, primary `labelColor`), number color `tertiaryLabelColor`, token colors via `SyntaxHighlighter.color(for:)`. Constants: `contentInset = 106`, `trailingInset = 8`, `rowHeight = 22 * scale`, `headerHeight = 32 * scale`, `advance` = advance of the space glyph in the content font.
- [ ] **Step 2: Failing tests** for the store: same `(contentKey, type, highlighted, styleVersion)` returns the identical `CTLine` object (`===`) and increments `DiffRenderStats.lineBuilds` once; bumping `styleVersion` rebuilds; a line with tokens applies a different foreground color at a token range than outside it (read back with `CTLineGetGlyphRuns` + `CTRunGetAttributes`).
- [ ] **Step 3: Implement `DiffTextLayoutStore`** (`@MainActor final class`): `func line(for line: DiffLine, tokens: [SyntaxToken]?, context: DiffRenderContext) -> CTLine` using `DiffGenerationalCache` (capacity 4 000). Build an `NSAttributedString` of `DiffTextMetrics.displayString` (or the expanded ASCII) with `kCTFontAttributeName` and `kCTForegroundColorAttributeName` (CGColor), then `CTLineCreateWithAttributedString`. Token ranges are mapped through the tab expansion (keep an offset map only when the text contains tabs). Also `func label(_ string: String, font: CTFont, color: CGColor, version: Int) -> CTLine` for numbers/prefix (cache by string + version). Wrap builds in `DiffSignpost.interval("lineBuild")` and bump the debug counter.
- [ ] **Step 4:** Run → PASS. Build. Checkpoint.

### Task 5: `DiffLongLineStore` (+ adopt in `DiffLongLineContent`)

**Files:**
- Create: `macgit/Views/Common/Diff/DiffLongLineStore.swift`
- Modify: `macgit/Views/Common/DiffLongLineContent.swift`
- Create: `macgitTests/DiffLongLineStoreTests.swift`

- [ ] **Step 1: Failing tests**
  - Requesting the same 500 000-char ASCII line from 5 callers before completion triggers exactly one preparation (`DiffRenderStats.longLinePreparations == 1`), and all callers are notified.
  - ASCII window for viewport `x: 1_000_000, width: 1_200` at advance 7.2 covers columns `[floor(1_000_000/7.2) - 64, ceil(1_001_200/7.2) + 64]` and its `CTLine` width ≈ column count × advance (±1 pt).
  - A CJK long line produces `.chunked` and the window uses `DiffLongLineLayout.visibleChunks(in:)`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Implement** (spec §5.5)

```swift
@MainActor
final class DiffLongLineStore {
    enum Prepared: Sendable { case ascii(bytes: [UInt8], columns: Int), chunked(DiffLongLineLayout) }
    struct Key: Hashable { let contentKey: Int; let fontKey: Int }
    static let shared = DiffLongLineStore()           // used by DiffLongLineContent

    private var prepared = DiffGenerationalCache<Key, Prepared>(capacity: 64)
    private var inFlight: [Key: Task<Void, Never>] = [:]
    private var waiters: [Key: [() -> Void]] = [:]
    private var windows = DiffGenerationalCache<WindowKey, CTLine>(capacity: 256)

    func prepared(for line: DiffLine, font: CTFont, fontKey: Int, onReady: @escaping () -> Void) -> Prepared?
    func window(for prepared: Prepared, key: Key, viewport: ClosedRange<CGFloat>, context: DiffRenderContext)
        -> [(x: CGFloat, line: CTLine)]
}
```

  Preparation runs in `Task.detached(priority: .userInitiated)` inside `DiffSignpost.interval("longLinePrepare")`: `DiffTextMetrics.asciiColumns` → `.ascii(expandTabs)`; otherwise `DiffLongLineLayout.prepare`. Windows are cached by `(key, firstColumnOrChunk, lastColumnOrChunk, styleVersion)`; quantize the ASCII window start to multiples of 256 columns so small horizontal moves reuse the same `CTLine`.
- [ ] **Step 4: `DiffLongLineContent`** — replace `@State layout` + `.task` preparation with a lookup in `DiffLongLineStore.shared` (`.chunked` only, since this view still renders with SwiftUI `Text` per chunk). Keep the placeholder and `help`. Recycled rows in `CodeBlockView`/`ConflictCodeView` now reuse prepared layouts.
- [ ] **Step 5:** Run `DiffLongLineStoreTests`, `DiffLongLineLayoutTests` → PASS. Build. Checkpoint.

### Task 6: `DiffHighlightStore`

**Files:**
- Create: `macgit/Views/Common/Diff/DiffHighlightStore.swift`
- Create: `macgitTests/DiffHighlightStoreTests.swift`

- [ ] **Step 1: Failing tests** — `prefetch` of 100 short lines runs one batch (one detached task) and afterwards `tokens(for:)` returns non-nil for all; long lines (> 4096 bytes) are never tokenized; a batch started with identity `A` is discarded after `reset(identity: B)`; when disabled (`isEnabled = false`) nothing is scheduled.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Implement** (spec §5.6): cache `DiffGenerationalCache<TokenKey, [SyntaxToken]>(capacity: 8_000)` keyed by `(contentKey, language)`; `inFlight: Set<TokenKey>`; `onTokensReady: (() -> Void)?` set by the coordinator (redraws visible canvases). Batch body runs `SyntaxTokenizer.tokens` for each `(key, text)` inside `DiffSignpost.interval("highlightBatch")` and returns `[(TokenKey, [SyntaxToken])]`.
- [ ] **Step 4:** Run → PASS. Build. Checkpoint.

### Task 7: `DiffWidthIndex`

**Files:**
- Create: `macgit/Views/Common/Diff/DiffWidthIndex.swift`
- Create: `macgitTests/DiffWidthIndexTests.swift`

- [ ] **Step 1: Failing tests** — `width(for:)` is non-zero immediately after `reset(hunks:)` (estimate from `widestLineCandidate`); after `measure(priority: [visible indices])` completes, the visible hunks report exact width first (order of `onWidthChanged` callbacks starts with the visible indices); an ASCII hunk's exact width equals `maxColumns × advance + 114`; re-`reset` with the same hunk ids keeps exact widths without recomputation.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Implement** (spec §5.7). Off-main loop checks `Task.isCancelled` per line; ASCII via `DiffTextMetrics.asciiColumns`, long non-ASCII via `DiffLongLineLayout.measuredWidth`, short non-ASCII via `CTLineGetTypographicBounds`. Results keyed by `(hunk.id, fontKey)`. Callback `onWidthChanged: (Int) -> Void` per finished hunk.
- [ ] **Step 4:** Run → PASS. Build. Checkpoint.

### Task 8: `DiffLineSelection` and `DiffMenuModel`

**Files:**
- Create: `macgit/Views/Common/Diff/DiffLineSelection.swift`
- Create: `macgit/Views/Common/Diff/DiffMenuModel.swift`
- Create: `macgitTests/DiffLineSelectionTests.swift`, `macgitTests/DiffMenuModelTests.swift`

- [ ] **Step 1: Failing selection tests** (spec §4.2): plain click on a context line → unchanged; plain click → `{line}`; ⌘-click toggles; ⇧-click selects only changed lines between anchor and target; ⇧⌘-click is a symmetric difference; ⇧-click without an anchor in this hunk behaves like plain click; `expandedSelectedLines` returns the whole contiguous `+/-` block for any selected line in it, in hunk order.
- [ ] **Step 2: Failing menu tests** — table-driven over `DiffMenuContext` combinations, asserting the exact `[DiffMenuEntry]` sequence produced today by `hunkContextMenu`, `lineContextMenu` and `commitPatchMenu` (`DiffView.swift:312-418`), e.g.:

```swift
func testUnstagedRowWithSelectionOnThatRow() {
    let entries = DiffMenuModel.entries(for: .init(
        scope: .row, lineIsChanged: true, lineIsSelected: true, canInteract: true,
        isStaged: false, hasCommitPatch: false, commitPatchDisabledReason: nil, hasSelectedLines: true))
    XCTAssertEqual(entries, [
        .action("Stage Hunk", .stageHunk, enabled: true),
        .action("Discard Hunk", .discardHunk, enabled: true),
        .divider,
        .action("Stage Selected Lines", .stageSelectedLines, enabled: true),
        .action("Discard Selected Lines", .discardSelectedLines, enabled: true),
        .divider,
        .action("Copy", .copyLine, enabled: true),
    ])
}
```

  Cover: staged row/hunk, untracked/conflict (no stage items), commit-patch present with and without disabled reason (note entry), commit-patch with only the clicked changed line (no selection), header scope (`Copy Hunk`).
- [ ] **Step 3:** Run → FAIL. **Step 4: Implement** both as `nonisolated enum`s with `Equatable` entries. `DiffMenuAction`: `applyHunk, revertHunk, applySelected, revertSelected, stageHunk, unstageHunk, discardHunk, stageSelectedLines, unstageSelectedLines, discardSelectedLines, copyLine, copyHunk`.
- [ ] **Step 5:** Run → PASS. Build. Checkpoint.

### Task 9: `DiffActionController` and `DiffHunkHeaderView`

**Files:**
- Create: `macgit/Views/Common/Diff/DiffActionController.swift`
- Create: `macgit/Views/Common/Diff/DiffHunkHeaderView.swift`

- [ ] **Step 1: `DiffActionController`** (`@MainActor final class`): properties `file`, `repositoryURL`, `undoManager`, `onRefresh`, `onError`, `onCommitPatch`, `commitPatchDisabledReason`, `selection: () -> Set<UUID>`, `setSelection: (Set<UUID>) -> Void`, `allHunks: () -> [DiffHunk]`. Computed `canInteract`, `isStaged` (same rules as `HunkView`). `func perform(_ action: DiffMenuAction, hunk: DiffHunk, line: DiffLine?)` implements each action by porting `stageHunk`, `unstageHunk`, `stageSelectedLines`, `unstageSelectedLines`, discard variants, `performPatchAction`, `perform`, `commitLineIDs`, the commit-patch closures from `DiffView.body` and the pasteboard copies — same patches, labels, undo entries and error messages. `func menuContext(scope:hunk:line:) -> DiffMenuContext`.
- [ ] **Step 2: `DiffHunkHeaderView`** — SwiftUI view with value input `DiffHunkHeaderInput: Equatable` (`header`, `addedCount`, `removedCount`, `textScale`, `canInteract`, `isStaged`, `hasCommitPatch`, `commitPatchDisabledReason`, `hasSelectedLines`) plus `let controller: DiffActionController` and `let hunk: DiffHunk`. Visuals per spec §4.1 (port `nativeHeader`). The `Changes` menu and `.contextMenu` render `DiffMenuModel.entries` with a shared `DiffMenuEntriesView` (`ForEach` → `Button`/`Divider`/`Text`).
- [ ] **Step 3:** Build (both types unused so far). Checkpoint.

### Task 10: `DiffHunkCanvasView`

**Files:**
- Create: `macgit/Views/Common/Diff/DiffHunkCanvasView.swift`
- Create: `macgitTests/DiffHunkCanvasViewTests.swift`

- [ ] **Step 1: Failing tests**
  - `rowIndex(at:)` maps points to rows with `sliceStart` applied; points in the gap after the last row return `nil`.
  - Drawing into an offscreen `NSBitmapImageRep` (call `cacheDisplay(in:to:)`) a hunk of 1 000 000 lines at `sliceStart = 15_000_000` increments `DiffRenderStats.lineBuilds` by at most the visible row count (~28 + label lines) and the canvas has no subviews.
  - A selected added row is drawn with the accent background (sample a pixel in the gutter area) and an unselected added row with the green background.
  - With a 500 000-char ASCII line at horizontal offset 2 000 000, drawing builds exactly one window `CTLine` for that row.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Implement** (spec §5.4)

```swift
struct DiffCanvasSource {
    let hunk: DiffHunk
    let sliceStart: CGFloat
    let offset: CGFloat           // horizontal content offset
    let selection: Set<UUID>
    let identity: AnyHashable?
}

@MainActor
final class DiffHunkCanvasView: NSView {
    unowned(unsafe) var context: DiffRenderContext!
    weak var layouts: DiffTextLayoutStore?
    weak var longLines: DiffLongLineStore?
    weak var highlights: DiffHighlightStore?
    weak var actions: DiffActionController?
    var onSelectionChange: ((Set<UUID>, UUID?) -> Void)?
    var anchor: UUID?
    var source: DiffCanvasSource? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let source, let cg = NSGraphicsContext.current?.cgContext else { return }
        DiffSignpost.interval("canvasDraw") {
            cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            let rows = DiffHunkGeometry.visibleLines(
                start: source.sliceStart + dirtyRect.minY, height: dirtyRect.height,
                lineHeight: context.rowHeight, count: source.hunk.lines.count)
            for index in rows { drawRow(index, source: source, in: cg) }
            highlights?.prefetch(source.hunk.lines, around: rows)
        }
    }
    // drawRow: background fill over bounds.width; numbers/prefix via layouts.label;
    // content via layouts.line (short) or longLines.window (long) / placeholder.
    // x = contentCoordinate - source.offset; baseline per spec §5.4.
}
```

  - `mouseDown`: `rowIndex(at:)` → `DiffLineSelection.apply` with `event.modifierFlags` → `onSelectionChange`.
  - `menu(for:)`: build `NSMenu` from `DiffMenuModel.entries(for: actions.menuContext(scope: .row, …))`; each item's target is a small `DiffMenuTarget` holding `(action, hunk, line)` and calling `actions.perform`. Keep a strong reference to targets in `NSMenuItem.representedObject`.
  - `viewDidChangeEffectiveAppearance` → ask the coordinator (closure `onAppearanceChange`) to update `DiffRenderContext`.
- [ ] **Step 4:** Run → PASS. Build. Checkpoint.

### Task 11: Rework `DiffNativeHunkView`

**Files:**
- Modify: `macgit/Views/Common/DiffNativeHunkView.swift`
- Modify: `macgitTests/DiffNativeHunkViewTests.swift`

- [ ] **Step 1: Retarget tests first** (spec §7): replace `cells`/`updateLines` usage.
  - `testSmallHunkDoesNotRedrawForEachVerticalScrollTick`: after the first draw, moving the viewport across a small hunk causes `DiffRenderStats.canvasDraws` to stay constant and the scroll frame to stay equal.
  - `testLargeHunkCanvasNeverExceedsViewport`: for 1 000 000 lines and content width 1 000 000, `canvas.frame.width <= 600`, `canvas.frame.height <= 600`, `linesView.subviews == [canvas]`.
  - Keep `testHunksOwnIndependentNativeHorizontalOffsets` and `testRestoredOffsetWaitsForAsynchronousWidthMeasurement` unchanged.
  - `testHorizontalScrollMovesCanvasWithClip`: scrolling the clip to x = 50 000 sets `canvas.frame.minX == 50 000` and `canvas.source?.offset == 50 000`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Implement** (spec §5.11)
  - `header` becomes `let header = NSHostingView<DiffHunkHeaderView?>(rootView: nil)` (or an `Optional`-wrapping container view) with `sizingOptions = []`; `func setHeader(_ input: DiffHunkHeaderInput, view: () -> DiffHunkHeaderView)` assigns `rootView` only when `input != lastHeaderInput` (bump `DiffRenderStats.headerHostAssignments`).
  - `lines` → `DiffHunkLinesView` (spacer) containing `canvas`.
  - Remove `cells`, `spareCells`, `rowLayout`, `rowRange`, `updateLines`.
  - In `updateGeometry` and in the horizontal bounds observer: `canvas.frame = CGRect(x: clip.bounds.minX, y: 0, width: clip.bounds.width, height: sliceHeight)`; when `sliceStart` or offset changed, set a new `canvas.source` (with the new `sliceStart`/`offset`). `onHorizontalScroll` now reports the raw offset (no 256 pt quantization needed for long lines; the store quantizes).
  - Remove `draw(_:)`; in `init`: `wantsLayer = true; layer?.cornerRadius = 8; layer?.borderWidth = 1; layer?.masksToBounds = true`; set `borderColor` in `viewDidChangeEffectiveAppearance` and `init` via `effectiveAppearance.performAsCurrentDrawingAppearance`.
- [ ] **Step 4: Temporary shim** so the old `DiffNativeTable` keeps building until Task 12: keep `var cells: [Int: DiffNativeCell] { [:] }` and `func updateLines(lineCount:lineHeight:refresh:configure:) {}` marked `@available(*, deprecated)`. (The old table renders headers only during this window; that is expected and lasts one task.) Run `DiffNativeHunkViewTests`, `DiffHunkGeometryTests` → PASS.
- [ ] **Step 5:** Build. Checkpoint.

### Task 12: Coordinator rework and `DiffView` switch

**Files:**
- Modify: `macgit/Views/Common/DiffNativeTable.swift`
- Modify: `macgit/Views/Common/DiffView.swift`

- [ ] **Step 1: `DiffNativeTable` signature** (spec §5.10) — non-generic:

```swift
struct DiffNativeTable: NSViewRepresentable {
    let hunks: [DiffHunk]
    let contentIdentity: AnyHashable?
    let textScale: CGFloat
    let syntaxHighlighting: Bool
    let fileExtension: String
    let selectedLineIDs: Set<UUID>
    let actions: DiffActionController
    let onSelectionChange: (Set<UUID>, UUID?) -> Void
    let headerInput: (DiffHunk) -> DiffHunkHeaderInput
}
```

- [ ] **Step 2: Coordinator**
  - Own `DiffRenderContext`, `DiffTextLayoutStore`, `DiffLongLineStore` (per table instance; `DiffLongLineContent` keeps `.shared`), `DiffHighlightStore`, `DiffWidthIndex`.
  - `offsets: [UUID: CGFloat]` keyed by hunk id.
  - `apply()` implements the five-step comparison of spec §5.10. On identity change call `scroll.contentView.scroll(to: .zero)` and `reflectScrolledClipView`. On same-identity hunk change, capture `bounds.minY` before rebuilding geometry and restore it clamped to `max(0, geometry.height - bounds.height)`.
  - `layout(_:)` no longer takes `refresh`; for each visible panel: `updateGeometry` (width from `DiffWidthIndex`), header via `setHeader` (input compared), canvas wiring (stores, `actions`, `onSelectionChange`) only when the panel is new/recycled, `canvas.source` updated.
  - `DiffWidthIndex.onWidthChanged(index)` → if that hunk is visible, `updateGeometry` for that panel only.
  - `DiffHighlightStore.onTokensReady` and long-line `onReady` → `needsDisplay = true` on visible canvases.
  - Observer: `addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: nil)` and wrap `layout` in `DiffSignpost.interval("layout")`.
  - `stop()` cancels width/highlight/long-line tasks owned by this table.
- [ ] **Step 3: `DiffView`**
  - Add `contentIdentity: AnyHashable?` init parameter with default `nil`; compute `effectiveIdentity = contentIdentity ?? AnyHashable(file?.path ?? filePath ?? "")` combined with `gitRef`.
  - Create `@State private var actions = DiffActionController()`; update its properties in `body` (cheap assignments, no observation).
  - Replace the `DiffNativeTable { … }` closure with the new initializer. `onSelectionChange` writes `selectedLineIDs`/`lastSelectedLineID`.
  - Remove `.id(hunks.first?.id)` and the `highlightCache` state/`onChange` handlers.
  - `.onChange(of: effectiveIdentity)` → clear selection and anchor. `.onChange(of: hunks.map(\.id))` → `selectedLineIDs.formIntersection(Set(hunks.lazy.flatMap(\.lines).map(\.id)))` only when the selection is non-empty.
- [ ] **Step 4:** Build. Run all diff tests: `DiffIdentityTests`, `DiffTextMetricsTests`, `DiffGenerationalCacheTests`, `SyntaxTokenizerTests`, `DiffTextLayoutStoreTests`, `DiffLongLineStoreTests`, `DiffHighlightStoreTests`, `DiffWidthIndexTests`, `DiffLineSelectionTests`, `DiffMenuModelTests`, `DiffHunkCanvasViewTests`, `DiffNativeHunkViewTests`, `DiffHunkGeometryTests`, `DiffLongLineLayoutTests`, `DiffPatchBuilderTests`, `CommitPatchIntegrationTests`.
- [ ] **Step 5: Visual parity check** — before deleting anything, stash a screenshot of the old build (from `main`) and the new build for: unstaged file (light + dark), staged file, untracked file, conflict file, history commit with Apply/Revert menu, text scale min/max, syntax highlighting on/off. Fix every difference against spec §4.1.
- [ ] **Step 6:** Checkpoint.

### Task 13: Accessibility

**Files:**
- Modify: `macgit/Views/Common/Diff/DiffHunkCanvasView.swift`

- [ ] **Step 1:** `accessibilityRole = .group`, `accessibilityLabel = hunk.header`. `accessibilityChildren()` returns cached `NSAccessibilityElement`s for rows in the current slice: role `.staticText`, frame in screen coordinates (`NSAccessibility.screenRect(fromView:rect:)`), label `"<Added|Removed|Context> line <new ?? old>: <first 200 characters>"`, `isAccessibilitySelected` from selection. Rebuild only when `source` changes.
- [ ] **Step 2:** Verify with Accessibility Inspector that rows are reachable and announced. Build. Checkpoint.

### Task 14: Delete dead code

**Files:**
- Delete: `macgit/Views/Common/DiffNativeCell.swift`, `macgit/Views/Common/DiffLineHighlightCache.swift`
- Modify: `macgit/Views/Common/DiffView.swift` (delete `HunkView`; keep `DiffLineView` for `CommitFilePreviewContent`)
- Modify: `macgit/Views/Common/DiffNativeHunkView.swift` (remove any deprecated bridging left from Task 11)

- [ ] **Step 1:** Delete the files/types; `rg "HunkView\b|DiffNativeCell|DiffLineHighlightCache"` must return nothing outside `DiffHunkHeaderView`/`DiffNativeHunkView` names.
- [ ] **Step 2:** Confirm `DiffLineView` still compiles for `CommitFilePreviewContent` (it never used `DiffLineHighlightCache`; it uses `CommitFilePreviewHighlightCache`). If `DiffLineView`'s `highlightCache` parameter was only used by `HunkView`, remove that parameter and its deferred-highlight path.
- [ ] **Step 3:** Build and run the full diff test list from Task 12. Checkpoint.

### Task 15: Verification

- [ ] **Step 1: Performance** — Release build, fixture repo from Task 0. In Instruments (Time Profiler + Animation Hitches + Points of Interest/`DiffView` signposts) record continuous trackpad scrolling for 10 s on each fixture file. Accept when: `layout` + `canvasDraw` per tick ≤ 2 ms p95; no hitches > 1 frame during steady scrolling; no `NSHostingView` allocations during scrolling (Allocations instrument, filter `NSHostingView`); memory stays flat after scrolling the 200 000-row file top to bottom twice.
- [ ] **Step 2: Long lines** — scroll `minified.js` and `cjk.txt` horizontally end to end, then vertically away and back: `DiffView/longLinePrepare` fires once per line.
- [ ] **Step 3: Refresh stability** — in the 2 000-hunk file, scroll to the middle, scroll one hunk horizontally, stage a hunk below the viewport: vertical position and that hunk's offset are kept; select lines in another hunk, discard a different hunk: selection of still-existing lines remains.
- [ ] **Step 4: Behavior sweep** against spec §4.2 in File Status, Stashes, History detail (Apply/Revert), Pull Request changes, Reference comparison, Commit patch review/conflict sheets.
- [ ] **Step 5:** Record “after” numbers next to the Task 0 baseline in the PR description. Checkpoint.
