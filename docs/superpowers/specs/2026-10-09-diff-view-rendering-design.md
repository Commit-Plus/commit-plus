# Diff View Rendering Rewrite — Design Spec

**Date:** 2026-10-09
**Scope:** The hunk/row rendering path behind `DiffView` (`macgit/Views/Common/DiffView.swift`, `DiffNativeTable.swift`, `DiffNativeHunkView.swift`, `DiffNativeCell.swift`, `DiffLineHighlightCache.swift`) plus the shared pieces it depends on (`GitDiffModels.swift`, `SyntaxHighlighter.swift`, `DiffLongLineLayout.swift`).
**Approach:** Keep the AppKit skeleton that already works (outer `NSScrollView`, per-hunk panel recycling, per-hunk native horizontal scroll, `DiffHunkGeometry`). Replace everything that runs SwiftUI per row with a single drawing canvas per visible hunk, and move all text work (measurement, highlighting, long-line preparation) into content-keyed caches that survive cell recycling and refreshes.
**Implementation plan:** `docs/superpowers/plans/2026-10-09-diff-view-rendering-plan.md`

---

## 1. Background

Small hunks scroll smoothly. Files with large bulk changes (tens of thousands of rows in one hunk) and hunks containing lines of hundreds of thousands of characters stutter. Root causes, in order of impact:

| # | Problem | Location |
|---|---|---|
| P1 | For a hunk taller than the viewport, the native slice follows the viewport pixel by pixel: `sliceStart` changes on every `boundsDidChange`, so `horizontalScroll.frame`, `lines` frame size and **every visible cell frame** are reassigned each tick. `rowLayout` contains `sliceStart`, so the early-return guard never fires. Each frame change re-runs layout in a `NSHostingView`. | `DiffNativeHunkView.swift:70-72`, `:98` |
| P2 | Every row is an `NSHostingView<AnyView>`. `configure` assigns a new `AnyView(...).id(identity)`, so SwiftUI cannot diff; it tears down and rebuilds the row tree (4 `Text`, `.task`, `.onTapGesture`, `.contextMenu`). Recycling saves the `NSView`, not the SwiftUI graph. `.contextMenu` per row is expensive on macOS. | `DiffNativeTable.swift:185`, `DiffView.swift:297-309` |
| P3 | `apply()` always calls `layout(scroll, refresh: true)`. `DiffNativeTable` carries a non-Equatable `content` closure, so any re-evaluation of `DiffView` (one-line selection, any `AdvancedSettingsStore` publish, a parent refresh) reconfigures every visible header and row. | `DiffNativeTable.swift:71` |
| P4 | Long lines are measured two or three times and never cached: `measureWidths` runs CoreText over every line of every hunk but keeps only the max; `DiffLongLineContent` re-runs `DiffLongLineLayout.prepare` each time a row is (re)created because its `@State layout` dies with the recycled cell. Until `measureWidths` finishes, all widths are `0`, so horizontal scrolling is impossible on large files. | `DiffNativeTable.swift:65,74-97`, `DiffLongLineContent.swift:42-43` |
| P5 | Syntax highlighting is `@MainActor`: each row schedules its own `Task`, yields once, then runs the regex on the main thread. Fast scrolling queues 30-40 regex passes on main per batch. | `DiffView.swift:677`, `:730`, `SyntaxHighlighter.swift:26` |
| P6 | `DiffLine.id`/`DiffHunk.id` are `UUID()` per parse. Any refresh (stage/discard, file watcher) changes every id: `.id(hunks.first?.id)` recreates the whole `NSScrollView` (scroll jumps to top, horizontal offsets lost), and the highlight cache is cleared. Sheets that call `DiffParser.parse` inside `body` (`CommitPatchConflictSheet.swift:100`, `CommitPatchReviewSheet.swift:51`) rebuild the table on every re-render. | `GitDiffModels.swift:38,68`, `DiffView.swift:131-142` |
| P7 | `DiffNativeHunkView.draw(_:)` strokes a border, which makes a panel as tall as the whole hunk (millions of points for large hunks) a drawing view with a backing store. | `DiffNativeHunkView.swift` (`draw`) |
| P8 | Minor: header counts filter/reduce `backgroundRuns` twice per configure; `DiffLineHighlightCache` eviction is O(n) (`removeFirst`). | `DiffView.swift:249-251`, `DiffLineHighlightCache.swift` |

## 2. Goals

1. **G1 — Vertical scroll:** scrolling a 200 000-row hunk creates or updates **zero** SwiftUI views per tick. Main-thread work per scroll tick ≤ 2 ms p95 (Release build, Apple Silicon), measured with the signposts in §5.12.
2. **G2 — Long lines:** horizontal scrolling of a 500 000-character line is smooth; the line's layout is prepared at most once while it stays in cache, independent of recycling.
3. **G3 — Selection:** clicking or shift-clicking rows only redraws canvases; it rebuilds no SwiftUI tree except a header whose `hasSelectedLines` flips.
4. **G4 — Refresh stability:** a refresh of the same file keeps vertical position, each hunk's horizontal offset, selection (for lines that still exist) and highlight/layout caches for unchanged content.
5. **G5 — Parity:** every behavior in §4 is preserved.
6. **G6 — Lean:** no feature flag and no parallel legacy renderer after the switch; dead code is deleted (§6).

**Non-goals:** side-by-side diff, intra-line word diff, text selection across rows (not supported today), sticky gutter (§9), changing `CommitFilePreviewContent`, `CodeBlockView`, `ConflictCodeView`, `PotentialConflictCodeBlockView` beyond adopting the shared long-line store (§5.5).

## 3. Architecture

```
DiffView (SwiftUI)                         selection @State, contentIdentity, image preview, empty state
└─ DiffNativeTable (NSViewRepresentable)   no generic content closure
   └─ NSScrollView (vertical)
      └─ DiffFlippedView (document, height = DiffHunkGeometry.height)
         └─ DiffNativeHunkView ×visible     recycled; layer border instead of draw(_:)
            ├─ header: NSHostingView<DiffHunkHeaderView>   concrete type, reassigned only when input changes
            └─ DiffHunkScrollView (horizontal, frame = visible slice, axis lock kept)
               └─ DiffHunkLinesView (spacer: contentWidth × sliceHeight, draws nothing)
                  └─ DiffHunkCanvasView  pinned to the clip's visible rect; draws rows; hit-testing; menus

Per table (owned by the Coordinator, shared by all panels):
  DiffRenderContext   fonts, metrics, colors, scale, appearance, styleVersion
  DiffTextLayoutStore CTLine cache for short rows (content-keyed)
  DiffLongLineStore   prepared long lines (ASCII windowed bytes or chunked CoreText layout), async + deduped
  DiffHighlightStore  syntax tokens computed off-main in batches
  DiffWidthIndex      per-hunk content width: instant estimate, refined off-main, visible-first
  DiffActionController  stage/unstage/discard/apply/revert/copy, shared by header and row menus
```

Key idea: rows are not views. A canvas no larger than the viewport redraws ~30-40 rows from cached `CTLine`s on each tick (well under 1 ms), which is far cheaper than moving dozens of hosting views. The nested `NSScrollView` per hunk stays, so momentum, elasticity, overlay scroller and per-hunk offsets keep native behavior.

## 4. Behavior contract (parity)

This is the source of truth. Old line numbers are for lookup only.

### 4.1 Layout and visuals
- Geometry unchanged: header height `32 × scale`, row height `22 × scale`, panels inset 4 pt horizontally, 8 pt gap, first panel at y = 4 (`DiffHunkGeometry`).
- Row, left to right (content coordinates, scroll horizontally with the row as today): 8 pt padding; old line number (monospaced 10 × scale, tertiary label color, right-aligned in 36 pt) + 6 pt; new line number (same) + 6 pt; prefix (`+`, `−`, space, `!`; monospaced 11 × scale semibold, line color at 70 %) centered in 14 pt; content starting at x = 106 pt (monospaced 12 × scale); 8 pt trailing. Content width of a hunk = widest text + 114 pt; row width = `max(viewport width, content width)`.
- Backgrounds: selected → accent 12 %; added → green 8 %; removed → red 8 %; conflict marker → purple 10 %; context/header → clear. Selection wins.
- Text color: syntax colors when highlighting is on (short lines only), otherwise primary; `.header` and `.conflictMarker` rows always use their line color (secondary / purple).
- Long line (UTF-8 > 4096 bytes, `DiffLineRendering.longLineByteThreshold`): plain text, never highlighted; while preparing, draw `Preparing long line…` in secondary color.
- Tabs render with 4-column tab stops (decision: matches the current ~28 pt default at 12 pt closely and makes ASCII columns exact). A trailing `\r` is not drawn.
- Panel: rounded 8 pt, 1 pt separator-color border; header background `secondary 6 %` with a 0.5 pt bottom separator.
- Header: hunk header text (monospaced 11 × scale medium, secondary, 1 line), `+N` green, `−N` red, spacer, then `Changes` menu (when `onCommitPatch` set), then `Stage` or `Unstage` + `Discard` (when interactive). Same `GlassButtonStyle` tints and sizes.

### 4.2 Interaction
- Click on a row selects only changed lines (`(old == nil) != (new == nil)`); other rows ignore clicks.
  - plain click → `{line}`, anchor = line
  - ⌘-click → toggle line, anchor = line
  - ⇧-click → changed lines between anchor and line (same hunk) replace the selection; ⇧⌘-click → symmetric difference; anchor = line. Missing anchor → behaves like plain click.
- Right-click on a row shows the row menu, on the header the hunk menu. Items, order and enablement exactly as `lineContextMenu`/`hunkContextMenu`/`commitPatchMenu` today, including the disabled-reason text item. Right-click does not change selection.
- `Copy` copies the full original line text (not tab-expanded, not truncated); `Copy Hunk` copies all lines joined by `\n`.
- Stage/unstage/discard build patches with `DiffPatchBuilder` exactly as today, expand selected lines to their whole change block (`expandedSelectedLines`), register undo only after success, clear selection and call `onRefresh` after success, `onError` on failure.
- Horizontal scrolling is per hunk and independent; offsets survive recycling and refresh (§5.10). Axis lock from `DiffHunkScrollView` is unchanged; vertical gestures over a hunk scroll the outer view.
- Syntax highlighting toggle, text scale and light/dark switch apply immediately without reloading the diff.
- Image preview, `EmptyStateView` for no hunks, and `prefersTextDiff` behavior are unchanged.

### 4.3 Identity and refresh
- Switching to another file (different `contentIdentity`) resets: scroll to top, horizontal offsets, selection, anchor.
- Re-rendering the same file with equal or changed hunks never recreates the `NSScrollView`.

## 5. Component design

### 5.1 Stable identity (`GitDiffModels.swift`)
- `DiffLine` gains `let contentKey: Int` (hash of `text`) and its `id` becomes `fileprivate(set) var id: UUID`. The public initializer is unchanged (random id) so standalone call sites keep compiling.
- `DiffHunk.init(header:lines:)` re-stamps ids deterministically:
  - `hunkSeed = hash(header, lines.count)`; `hunk.id = DiffIdentity.uuid(hunkSeed, 0x48554e4b)`.
  - `line.id = DiffIdentity.uuid(hash(hunkSeed, index, type, old, new), contentKey)`.
- `DiffIdentity.uuid(_:_:)` packs two `Int`s into the 16 UUID bytes. `Hasher` is seeded per process; ids are only used in memory, never persisted.
- `DiffHunk` also precomputes `addedCount` and `removedCount` (from `backgroundRuns`). Text metrics are **not** stored on the model; they are font-dependent and live in §5.3/§5.7.
- `DiffLineType` becomes `Hashable`.

### 5.2 `DiffRenderContext` (`@MainActor final class`)
Holds `textScale`, `syntaxHighlighting`, `fileExtension`, `isDark`, and derived values: `CTFont`s (content 12, numbers 10, prefix 11 semibold, all × scale), `ascent/descent`, `advance` (monospaced space advance), row/header heights, `contentInset = 106`, `trailingInset = 8`, and resolved `CGColor`s for every background, line color and token type. `styleVersion` increments when scale, highlighting, extension or appearance changes; caches key on it.

### 5.3 `DiffTextMetrics` (`nonisolated enum`, pure)
- `asciiColumns(_ text: String) -> Int?`: scans UTF-8 once; returns display columns for printable ASCII with tab expansion (`tabWidth = 4`), ignores a trailing `\r`; returns `nil` on any other byte.
- `expandTabs(_ text: String) -> [UInt8]` (ASCII only), `displayString(_:)` for short non-ASCII lines (tab expansion on `Character`s).
- Width of an ASCII line = `columns × advance` (exact for a monospaced font). Non-ASCII → CoreText typographic width of the display string.

### 5.4 `DiffHunkCanvasView` (drawing)
- `final class DiffHunkCanvasView: NSView`, flipped, `layerContentsRedrawPolicy = .onSetNeedsDisplay`, non-opaque. Frame = `(clip.bounds.minX, 0, clip.bounds.width, sliceHeight)` inside `DiffHunkLinesView`; on horizontal bounds change the canvas origin is updated and it is marked for display. The canvas is never wider than the viewport, so its layer stays small even when content is 10⁶ pt wide.
- Input: `DiffCanvasSource` (hunk, hunk index, `sliceStart`, horizontal offset, selection, render context, stores). Setting a source with an equal value does nothing.
- `draw(_:)`:
  1. `rows = DiffHunkGeometry.visibleLines(start: sliceStart + dirty.minY, height: dirty.height, …)`.
  2. Set `textMatrix = CGAffineTransform(scaleX: 1, y: -1)`.
  3. For each row: fill background across the canvas width; draw numbers and prefix (cached `CTLine`s keyed by number/prefix + `styleVersion`); draw content:
     - short line → `DiffTextLayoutStore.line(for:)` (highlighted if tokens available, else plain; plain lines are built synchronously — ≤ 4 KB is cheap).
     - long line → `DiffLongLineStore` window (§5.5) or the placeholder.
  4. Baseline = `rowTop + (rowHeight − (ascent + descent)) / 2 + ascent`; x = content coordinate − offset.
- Hit-testing: `mouseDown` maps `y` to row index, reads `event.modifierFlags`, calls `DiffLineSelection.apply` (§5.8) and reports the result through `onSelectionChange`. `menu(for:)` builds an `NSMenu` from `DiffMenuModel` (§5.8).
- After drawing, the canvas asks `DiffHighlightStore` and `DiffLongLineStore` to prefetch rows `visible ± one viewport`; when results arrive the stores mark interested canvases for display.

### 5.5 `DiffLongLineStore` (`@MainActor final class`)
- Key: `(contentKey, styleVersionForFont)`. Values:
  - `.ascii(bytes: [UInt8], columns: Int)` — tab-expanded bytes. Window drawing creates a `CTLine` only for columns `[floor(x0 / advance) − 64, ceil(x1 / advance) + 64]`, built with `String(decoding: bytes[a..<b], as: UTF8.self)`. Cost is proportional to the viewport, not the line.
  - `.chunked(DiffLongLineLayout)` — existing chunked CoreText layout for non-ASCII long lines; window = `visibleChunks(in:)`; per-chunk `CTLine`s cached in the store.
- Preparation runs in one detached task per key; concurrent requests for the same key share it (in-flight dictionary). Cancellation only when no canvas wants the key anymore and the file changes.
- Capacity: two-generation cache (§5.9) with ~64 entries; window `CTLine` cache ~256 entries.
- `DiffLongLineContent` (used by `CodeBlockView`, `ConflictCodeView`, `PotentialConflictCodeBlockView`) reads layouts from a shared static store instance instead of its own `@State`, so recycled rows there stop re-preparing too. Its rendering stays SwiftUI.

### 5.6 Highlighting off the main thread
- Extract `SyntaxTokenizer` (`nonisolated enum`) from `SyntaxHighlighter`: compiled rules cache behind `OSAllocatedUnfairLock`, `static func tokens(in text: String, language: String) -> [SyntaxToken]` where `SyntaxToken { range: NSRange; type: SyntaxTokenType }` is `Sendable`. `syntaxIdentifier(forLanguage:)`/`forFilePath:` become `nonisolated`. `SyntaxHighlighter` keeps its API and delegates to the tokenizer (no behavior change for other users).
- `DiffHighlightStore` (`@MainActor`): `tokens(for line) -> [SyntaxToken]?` (cache by `contentKey` + language); `prefetch(lines:)` collects missing, non-long, non-in-flight lines and tokenizes them in **one** detached task per batch; results inserted on main, then the registered canvases redraw. Batches are dropped if `contentIdentity` changed.
- `DiffTextLayoutStore` combines text + tokens + `DiffRenderContext` colors into a `CTLine` keyed by `(contentKey, type, highlighted, styleVersion)`.

### 5.7 `DiffWidthIndex`
- Per hunk id: `estimate` = `widestLineCandidate` columns × advance (instant, from the field `DiffHunk` already computes), replaced by `exact` computed off-main (`DiffTextMetrics` for ASCII, `CTLine`/`DiffLongLineLayout.measuredWidth` otherwise).
- Visible hunks are measured first; the remaining hunks follow in order. Each finished hunk updates the table via a callback (only that panel's `updateGeometry`). Results are keyed by `(hunk.id, fontKey)` and survive refreshes.

### 5.8 Selection, menus, actions
- `DiffLineSelection` (`nonisolated enum`, pure): `apply(tapAt:in:selection:anchor:shift:command:) -> (Set<UUID>, UUID?)` and `expandedSelectedLines(in hunk:, selection:) -> [DiffLine]` (moved from `HunkView`).
- `DiffMenuModel` (pure): builds `[DiffMenuEntry]` (`.action(title, DiffMenuAction, enabled)`, `.divider`, `.note(text)`) from a `DiffMenuContext` (scope row/hunk, line, `canInteract`, `isStaged`, `hasCommitPatch`, `commitPatchDisabledReason`, `hasSelectedLines`, `lineIsSelected`). The row menu (`NSMenu`) and the header menu (SwiftUI `ForEach` over the same entries) render it, so parity is enforced in one place.
- `DiffActionController` (`@MainActor final class`): owns file, repository URL, undo manager, callbacks and a selection accessor; implements every `DiffMenuAction` with the existing `GitStatusService.applyPatch` / `GitUndoEntryFactory.applyPatch` flow. Its stored callbacks are refreshed on every `updateNSView` without touching any view.

### 5.9 Caches
A tiny `DiffGenerationalCache<Key, Value>` (two dictionaries; lookup promotes from the old generation; when the current generation exceeds `capacity / 2` the old one is dropped). O(1) amortized, bounded at `capacity`. Used by the layout, highlight and long-line stores. (`BoundedMemoryCache` is O(n) per touch and stays untouched for its current users.)

### 5.10 Coordinator change detection and viewport preservation
- `DiffNativeTable` takes `hunks`, `contentIdentity: AnyHashable?`, `textScale`, `syntaxHighlighting`, `fileExtension`, `selectedLineIDs`, `headerInputs` (value) and `actions: DiffActionController`. No view-builder closure.
- `apply()` compares, in this order:
  1. `contentIdentity` changed → full reset (scroll to top, offsets cleared, panels released).
  2. hunk ids changed (same identity) → rebuild geometry; keep `contentView.bounds.minY` (clamped to the new height); keep offsets keyed by **hunk id** (was index); re-source visible panels.
  3. scale/highlighting/extension/appearance → bump `styleVersion`, update geometry if scale changed, redraw canvases, reconfigure headers.
  4. selection changed → redraw visible canvases; reconfigure a header only if its `hasSelectedLines` flipped.
  5. otherwise → nothing.
- Scroll observation uses `queue: nil` so layout runs synchronously in the bounds change.

### 5.11 `DiffNativeHunkView` changes
- Remove `cells`, `spareCells`, `updateLines`; add `canvas` and `func updateCanvas(source:)`.
- Header becomes `NSHostingView<DiffHunkHeaderView>` with `sizingOptions = []`, rootView assigned only when the header input changes.
- Remove `draw(_:)`; `wantsLayer = true`, `layer.cornerRadius = 8`, `layer.borderWidth = 1`, border color refreshed in `viewDidChangeEffectiveAppearance`.
- `updateGeometry` keeps the slice logic and its public signature; it now also positions the canvas.

### 5.12 Instrumentation
- `DiffSignpost` with an `OSSignposter` (category `DiffView`): intervals `layout`, `canvasDraw`, `highlightBatch`, `longLinePrepare`, `widthIndex`.
- `#if DEBUG` counters (`DiffRenderStats`): header host assignments, canvas draws, `CTLine` builds, long-line preparations. Tests assert on them.

## 6. Files

| Action | File |
|---|---|
| Create | `Views/Common/Diff/DiffRenderContext.swift`, `DiffTextMetrics.swift`, `DiffGenerationalCache.swift`, `DiffTextLayoutStore.swift`, `DiffLongLineStore.swift`, `DiffHighlightStore.swift`, `DiffWidthIndex.swift`, `DiffLineSelection.swift`, `DiffMenuModel.swift`, `DiffActionController.swift`, `DiffHunkHeaderView.swift`, `DiffHunkCanvasView.swift`, `DiffSignpost.swift`; `Services/SyntaxTokenizer.swift` |
| Modify | `Services/GitDiffModels.swift`, `Services/SyntaxHighlighter.swift`, `Views/Common/DiffView.swift`, `DiffNativeTable.swift`, `DiffNativeHunkView.swift`, `DiffLongLineContent.swift` |
| Delete | `Views/Common/DiffNativeCell.swift`, `Views/Common/DiffLineHighlightCache.swift`, `HunkView` (inside `DiffView.swift`) |
| Keep | `DiffLineView` (used by `CommitFilePreviewContent`), `DiffHunkGeometry`, `DiffHunkScrollView`, `DiffFlippedView`, `DiffLongLineLayout`, `DiffPatchBuilder`, all `DiffView` call sites (signature stays source-compatible; `contentIdentity` defaults to `file?.path ?? filePath`) |

The project uses synchronized folders: new files and the `Diff/` subfolder need no `.xcodeproj` edits.

## 7. Testing

- Unit (new): `DiffIdentityTests`, `DiffTextMetricsTests`, `DiffGenerationalCacheTests`, `SyntaxTokenizerTests` (token parity with `SyntaxHighlighter` on a corpus per language), `DiffLineSelectionTests`, `DiffMenuModelTests`, `DiffLongLineStoreTests` (one preparation per key, window bounds), `DiffWidthIndexTests`.
- Retarget `DiffNativeHunkViewTests`: replace cell assertions with canvas assertions (a single canvas, never wider than the viewport, no subviews per row, no redraw for a small hunk while scrolling, offsets independent and restored).
- Keep `DiffHunkGeometryTests`, `DiffLongLineLayoutTests`, `DiffPatchBuilderTests`, `CommitPatchIntegrationTests` green.
- Manual: generated fixture repository (plan Task 0) — 200 000-row hunk, 2 000 small hunks, one 500 000-char ASCII line, one 200 000-char CJK line, CRLF file, tabs; light/dark; scale changes; stage/unstage/discard hunk and lines; apply/revert in history.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Custom drawing drifts visually from the SwiftUI rows | §4.1 is explicit; compare screenshots side by side before deleting the old path (plan Task 12). |
| VoiceOver loses row elements | Canvas exposes visible rows as `NSAccessibilityElement` children (role static text, label “Added line 12: …”, first 200 characters). |
| Long-line tooltip (`.help`) is lost | Accepted; placeholder text remains. Can be re-added with `addToolTip(_:owner:userData:)` per long row if missed. |
| Deterministic ids collide | Line id mixes hunk seed, index, type, numbers and content hash; ids are scoped to one file's diff. |
| Off-main highlighting races a file switch | Every batch carries `contentIdentity`; stale results are dropped. |
| Tab rendering changes slightly (4-column stops) | Documented decision; constant in one place. |

## 9. Follow-ups (not in this work)

- Sticky gutter (line numbers stay while scrolling horizontally) — trivial with the canvas (draw numbers at fixed x).
- Migrate `CommitFilePreviewContent` and `CodeBlockView` rows to the canvas renderer.
- Intra-line word diff highlighting.
