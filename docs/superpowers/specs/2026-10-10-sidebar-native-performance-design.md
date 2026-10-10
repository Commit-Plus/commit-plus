# Sidebar Native Rendering and Interaction — Design Spec

**Date:** 2026-10-10  
**Status:** Proposed; implementation and runtime measurements have not started.  
**Plan:** [Implementation plan](../plans/2026-10-10-sidebar-native-performance-plan.md)  
**Reference:** [PR #54](https://github.com/Commit-Plus/commit-plus/pull/54), especially `CommitFileNativeList` and `FileStatusNativeList`.

## 1. Problem and evidence

The sidebar feels slow when selecting, double-clicking, and dragging branches. The current implementation mixes a SwiftUI `List`, per-row native interaction overlays, per-row context menus, and presentation state held by `SidebarView`.

Source review establishes the following; it does not establish their relative wall-clock cost:

| Finding | Current source | Consequence |
| --- | --- | --- |
| `BranchNode.id` is initialized with `UUID()` | `Sidebar/BranchNode.swift`, `SidebarTreeBuilder.swift` | Rebuilding an unchanged tree changes every row ID; the list cannot preserve row identity across refreshes. |
| Visible arrays are computed during rendering | `SidebarView+Loading.swift`, `SidebarView.sidebarRows` | Parent updates repeat flattening; submodules also rebuild their tree and lookup dictionary. |
| Each leaf owns context-menu attachment and interaction machinery | `SidebarBranchRow.swift` | Shared component source does not mean shared menu ownership. The remote-tracking submenu sorts and enumerates remote refs. SwiftUI menu construction timing requires measurement; do not claim all menus are eagerly built every frame. |
| Selection happens on mouse-up | `SidebarBranchDragSource.swift`, `SidebarBranchDropTarget.swift` | No selected feedback while the mouse remains down. The native branch handler does not intentionally wait for a double-click timeout. |
| Current-branch drag builds payload before testing the 4 pt threshold | `SidebarBranchDropTarget.mouseDragged` | Small pointer movements create/encode payloads and write sidebar drag state before a drag begins. The non-current branch source already tests distance first. |
| Drag/hover and data share the parent update path | `SidebarView+DragDrop.swift`, `SidebarView.swift` | Transient interaction can cause unrelated row-input reconstruction. |
| Load generation is assigned after asynchronous branch reads | `SidebarView+Loading.swift` | Overlapping requests need explicit request ordering and repository identity checks, not only a token assigned after a result arrives. |

PR #54 provides the applicable pattern: reusable native cells, value-based change detection, and an event-time menu factory. Native rendering alone is insufficient if each update still rebuilds the model or reloads the entire table.

## 2. Scope and decisions

Replace the scrollable `SidebarView.sidebarList` with **one `NSScrollView` containing one `NSTableView`**, using a flattened, explicitly indented row snapshot. This matches the existing flattened tree model and supports heterogeneous section headers, folders, leaves, loading rows, and empty rows without nested scroll views.

All sidebar sections participate: Workspace/Git Flow, Branches, Worktrees, Tags, Remotes, Stashes, Submodules, and Subtrees. Branches are the first implementation slice; the final switch includes the complete list so another section does not retain the same per-item bottleneck.

Keep SwiftUI for the surrounding sidebar chrome, account/update surfaces, sheets, alerts, and popovers. Keep existing action policies, Git services, operation coordination, undo, notifications, and repository/window routing. No Git execution moves into native cells or the rendering coordinator.

Non-goals: change Git semantics, add multi-selection, redesign navigation, change Firebase contracts, change remote-fetch policy, or migrate the entire app's observation architecture. No third-party dependency. No parallel production renderer or permanent feature flag after cutover.

## 3. Architecture and ownership

```text
SidebarView — chrome, bindings, existing presentation and action routing
  Sidebar presentation store — section data, request generations, snapshots
  SidebarNativeList (NSViewRepresentable)
    Coordinator — installed snapshot, index maps, selection synchronization
    NSScrollView
      SidebarTableView — native pointer/keyboard/menu/drag routing
        reusable native header/folder/leaf/status cells
    Shared menu controller — one active menu tree, item IDs and typed actions
    Drag session state — decoded payload, source identity, current target
```

Proposed types live under `macgit/Views/MainWindow/Sidebar/Native/`, one type per file where practical. Reuse existing controllers/action structs; do not build a second business-action layer. The presentation store is a narrowly scoped `@MainActor` owner, not a replacement for `AppState` or `MainWindowView`.

### 3.1 Stable identity

- Define a typed `SidebarRowID` containing repository identity, section, row kind, and exact semantic key. Do not concatenate ambiguous strings or use `hashValue` as persistent identity.
- Ref keys use exact full ref/path; folder and leaf IDs differ even if their displayed path is equal. Branch, tag, and remote namespaces differ. Header/status IDs are section-specific.
- Repository identity follows the existing repository/window identity convention. Do not introduce filesystem canonicalization that changes linked-worktree behavior.
- Rename is removal plus insertion. Labels, badges, loading state, text scale, and sync counts are content, not identity.
- Worktrees/submodules/subtrees use their existing stable path/registry identity. Stashes require special care: `stash@{n}` is an action locator that shifts after deletion. Inspect `StashEntry` and use an object identity when available, with disambiguation for duplicate entries; resolve the current ref at action time. Never restore selection to another stash solely because its index was reused.
- Keep `SidebarSelection` as the external navigation contract. Maintain explicit ID-to-selection and selection-to-ID maps; do not silently change all selection consumers.

### 3.2 Snapshot and invalidation

`SidebarSnapshot` contains ordered row IDs, lookup maps, and immutable equatable row presentation values. Values contain only rendering and interaction eligibility inputs, not closures or entire unrelated dictionaries. Keep the current action router separately and update its reference without invalidating cell content.

| Change | Required work |
| --- | --- |
| Selection only | Update old/new native selection; no tree rebuild or structural reload. |
| Drag target changes | Redraw previous/new target and affected header only. |
| One badge changes | Replace that row's presentation value; update its visible cell if present. |
| Expand/collapse | Recompute the affected section's visible rows; insert/remove the resulting contiguous range. |
| Refs change | Rebuild the affected section's tree/index; publish one coherent snapshot. |
| Remote menu data changes | Invalidate menu data revision; do not reconfigure unrelated cells. |
| Text scale/appearance | Update style revision and affected geometry/colors; preserve identity and anchor. |
| Equal snapshot or chrome-only update | No row reconfiguration, tree work, or `reloadData()`. |

Construct trees, sorted remote indexes, and flattened row arrays only when their dependencies change, outside SwiftUI `body`. Cache invalidation must explicitly cover repository, section visibility, expansion, source records, relevant policy state, and style. For large transforms, use immutable Sendable input and pure off-main work; publish the matching generation on main. Do not introduce a detached task that reads live UI state.

Assign a request generation **before the first await**, scoped by repository and section. Reject stale completions after repository switches or newer requests. Coalesce equivalent pending refreshes; preserve distinct existing refresh meanings. Batch a section result into one publication. Retain existing local/remote notification routes and avoid extra fetches.

### 3.3 Native table updates and viewport

- Use native reusable cell views with labels, image views, and native controls. No SwiftUI hosting view, native overlay, context menu, observer, or task per dynamic leaf.
- Set identifiers by cell kind and clear old targets/content when recycling. Cell actions carry stable IDs, never a captured row index.
- Apply structural changes using a deterministic diff of ordered IDs. Content-only changes update changed cells/rows. Normal refreshes must not call full `reloadData()`; initial installation and repository reset may.
- Maintain ID-to-index maps, avoiding full-array scans for every mouse or selection event. O(n) reconciliation is acceptable when a new data snapshot arrives, not on scroll ticks or drag updates.
- Before structural/height changes, capture top visible ID plus pixel offset and selected ID. Restore using the same ID, then nearest surviving neighbour if removed. Clamp at document bounds.
- Background refresh must not scroll to selection. Explicit navigation may reveal its target. If a selection disappears, clear native highlight and use existing navigation fallback through the owner; never select an unrelated replacement index. Collapsing a folder can hide a still-valid logical selection without replacing it.
- When a source row is removed during a native drag, keep session state alive independently of cell lifetime and reject stale operations on completion.

## 4. Interaction contract

### 4.1 Selection, double-click, and keyboard

- Primary mouse-down on a selectable row paints native selection immediately, then publishes selection once through the existing selection action. No Git work or tree preparation precedes selected feedback. History data remains independently asynchronous.
- Non-selectable headers/folders toggle once per click and do not overwrite navigation selection. Preserve section persistence and existing expansion defaults.
- A double-click on an eligible branch invokes checkout exactly once; current branch remains protected. Remote and stash double actions retain their existing policy/confirmation paths. Inventory tag and worktree double actions before cutover.
- Do not attach competing SwiftUI gestures or duplicate AppKit action handlers. Use one explicit click state machine: mouse-down selection, threshold-based drag, eligible mouse-up double action. Dragging cancels pending activation.
- Embedded controls, disclosure buttons, and header menus consume their own hit area. Clicking them cannot also select, checkout, or start a drag. Replace the current hard-coded 96 pt trailing passthrough with actual control hit-testing.
- Arrow navigation, focus, type-to-select, and accessibility activation must continue working. Left/right collapse/expand folders; skip nonselectable status/header rows. Do not introduce new destructive keyboard shortcuts.
- Suppress delegate feedback while applying an external selection. Repeated clicks or the second click of a double-click must not restart an identical History filter unnecessarily.

### 4.2 Context menus

- `menu(for:)` hit-tests the clicked row, resolves its ID, and asks the shared controller for a menu. Blank space uses the existing sidebar creation/visibility menu. The clicked item, not the previously selected item, is the action target.
- Build zero item menus during snapshot generation, cell configuration, or scrolling. Retain only the active menu and action targets; release them on close and teardown.
- Preserve existing labels, ordering, destructive indications, enablement, shortcuts, and policies for every section. Right-click must not trigger checkout or change the History filter; any context highlight is separate from logical selection.
- Pre-sort remote refs once per remote-data revision. Populate large remote-tracking submenus on demand when opened, not for every branch row or on every parent update. Closing/reopening must use current data.
- Capture typed action + row identity + repository identity. Resolve the current entity and revalidate eligibility when invoked. Reject removed/renamed targets or repository switches; never retarget by row index or stale stash ref.
- Native menu and inline buttons route to the same existing callbacks/policies. Do not duplicate Git command implementation in an `NSMenuItem` target.

### 4.3 Drag and drop

- Track pointer origin; create/encode exactly one payload only after distance reaches 4 pt and the source is eligible. A click or sub-threshold movement creates none and writes no global payload state.
- Keep active session payload outside SwiftUI row state. Preserve `GitDragPayloadStore` interoperability with History/file/status sources and other windows.
- Cache decoded incoming payload for the drag session/pasteboard revision. Re-evaluate target and modifier-dependent policy on movement; do not decode and enumerate dragging images unnecessarily on every update.
- Update native hover feedback only when target, label, or acceptance changes. Option changes must update Merge/Rebase semantics even over the same target.
- Preserve existing target matrix by calling `GitDragDropPolicy`: branch/header, current branch, tags/header, remotes/header, stash header, and any other existing supported target. Preserve cross-repository rejection and confirmation/revalidation paths.
- Preserve commit preview point size, payload type, preview titles, source operation mask, and cleanup across successful, rejected, cancelled, and cross-window drags.
- Use one destination path per target. Remove duplicate SwiftUI `.onDrop` once equivalent native provider/pasteboard handling is verified.
- Auto-scroll near viewport edges must work without rebuilding snapshots. Ending a drag clears transient state exactly once, including when its source cell was recycled.

## 5. Parity checklist

Before replacement, record current actions and presentation from each row/section/menu implementation into implementation tests/checklists. This inventory is a migration gate, not permission to omit less common sections.

| Surface | Must preserve |
| --- | --- |
| Workspace/Git Flow | Visibility settings, Search callback, navigation tags, customization popover, PR creation, Git Flow command eligibility/recovery UI. |
| Branches | Hierarchy, current prefix emphasis, HEAD/detached presentation, sync/integration badges, update control, all branch/folder actions. |
| Remotes | Remote grouping, symbolic HEAD treatment, checkout/track/pull/compare/delete actions, remote drag semantics. |
| Tags | Hierarchy, checkout/details/compare/push/force-push/delete, move-tag drop target. |
| Stashes | Display title, immediate selection, asynchronous detail, apply/delete confirmation, drag preview and locator safety. |
| Worktrees | Labels, current/locked/missing states, open/terminal, create/checkout/move/lock/remove/prune actions and sheets. |
| Submodules/Subtrees | Visibility, hierarchy where present, status/availability, all lifecycle/configuration actions and error presentation. |
| Shared | Section ordering, indentation, spacing, native selection appearance, light/dark mode, text scale, narrow widths, scrollbar visibility, concrete hit-area hand cursor, tooltips. |

Accessibility must expose row name, type, selected/expanded state, badges where meaningful, and separate inline controls. Native view reuse must not leave stale accessibility labels or actions. Respect Reduce Motion and preserve keyboard focus across refreshes. A canvas is not required for sidebar text; use native accessible controls.

## 6. Performance and verification contract

Targets below are proposed acceptance budgets, not measured claims. Record hardware, OS, build configuration, row counts, expansion state, viewport size, and samples with results.

Create a disposable local Git fixture with 100 / 1,000 / 10,000 local branches and tags, nested folders, and remote-tracking refs generated locally (no network or changes to the working repository). Include collapsed/fully expanded and mixed-section snapshots, long Unicode names, duplicate display names across sections, and refreshes that alter only one badge or insert/delete a nearby row.

Instrument snapshot build/apply, cell create/configure, selection dispatch, menu build, payload encode/decode, and target changes. Avoid logging sensitive repository paths or payload content.

Deterministic acceptance:

- Equal refresh preserves all IDs and performs zero structural reloads/cell configurations.
- Selection-only and hover-only events perform zero tree builds, zero menu builds, and zero full-table reloads.
- First display allocates cells proportional to viewport plus normal reuse allowance, not total row count. Repeated scrolling reaches a bounded reuse plateau.
- Sub-threshold dragging encodes zero payloads; an accepted source drag encodes once.
- Content changes with equal IDs still update affected badges/labels; stable identity cannot hide stale data.
- Old-generation responses cannot replace current repository/section state. Menu actions cannot execute against stale or recycled targets.

Runtime targets in a Release build on the same documented Apple Silicon machine:

- Pointer-down to visible selection p95 <= 1 display refresh interval; separately measure synchronous handler work, targeting <= 2 ms p95. Do not count Git checkout completion as click latency.
- Sidebar-owned steady-scroll and drag-target processing <= 2 ms p95 per event; no recurring sidebar-attributable main-thread task above 8 ms in those paths.
- Top-level context menu opening <= 50 ms p95; measure large submenu population separately with the 10,000-ref fixture.
- Two complete scroll cycles followed by refresh/menu/drag cycles do not show unbounded cell, menu-target, observer, or payload retention.

These runtime checks require an available running app. **Do not launch/relaunch the app automatically under the user's current instructions.** Build for compilation; source tests and offscreen checks cannot prove interaction latency. If runtime access is unavailable, mark performance acceptance pending. Firebase bootstrap crashes are not evidence of a sidebar regression; do not repeatedly retry.

## 7. Completion criteria

All sidebar sections use the shared native list; source-based behavior parity and deterministic tests pass; build passes; dead row overlays/menu attachments are removed after checking external call sites. Runtime parity and performance results are recorded separately as passed or pending. Do not call the work performance-verified solely because compilation succeeds. No automatic commit, push, deployment, stash, or reset is part of this scope.
