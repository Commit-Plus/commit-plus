# Sidebar Native Rendering and Interaction — Implementation Plan

**Date:** 2026-10-10  
**Status:** Native renderer cutover implemented for all sections; app compilation passed, runtime acceptance pending.
**Spec:** [Design and acceptance contract](../specs/2026-10-10-sidebar-native-performance-design.md)

Implement in dependency order. This document authorizes no automatic commits, pushes, production changes, or app launches. Preserve unrelated working-tree changes. Use `rtk` for shell commands, keep Xcode build/test invocations sequential, and add AGPL notices to new Swift files.

## Implementation record — native cutover

The production sidebar now uses `SidebarNativeList` for every section. The old `List`, section renderers, row renderers and their SwiftUI context-menu trees have been removed from that path. Surrounding account/update chrome and presentation modifiers remain in SwiftUI.

- `SidebarNativeInput` compares immutable source values before `SidebarView+NativeRows` builds a snapshot. Selection-only updates synchronize an index; scroll/hover do not publish SwiftUI state. Existing section data stays with its current owner rather than being duplicated into a new store.
- `SidebarNativeList.Coordinator` maintains ID and selection indexes, applies structural insertions/removals, preserves a surviving viewport anchor, and updates instantiated cells. Native cells contain reusable labels, icons, progress indicators and accessory buttons, with no per-leaf hosting views.
- `SidebarView+NativeMenus` preserves the existing callback/policy routes. Right-click builds the clicked row's menu; tracking targets are populated when its submenu opens. Refresh invalidates open-menu actions. Rich popovers are hosted only when requested.
- The table owns selection, double-click, keyboard disclosure, drag sources, drop hit-testing and hover labels. It uses AppKit's drag threshold, caches payload decoding by pasteboard name/revision, rechecks drop policy and retains the existing commit-preview point-size correction. The legacy drop helper remains for that shared correction and its existing tests; it is not instantiated per row.
- Stash reads now include the object ID; selection follows an unambiguous object when reflog indices shift. Native duplicate-object IDs are disambiguated. Worktree/subtree loads now reject superseded completions; repository resets invalidate outstanding section generations. Branch sync results publish in a batch.
- `SidebarNativeListTests` adds regression cases for 10,000-row selection without a snapshot rebuild, hidden selection, reorder, row namespaces, stale menus, lazy submenus and cell reuse.

Validation: app builds passed during implementation. `build-for-testing` was attempted without executing tests; the shared test target fails on existing actor conformances to globally isolated protocols in Git Undo/AI and other test fixtures. No error was reported for the new sidebar test file. The final app build and diff check are recorded below. No app launch, XCTest execution, Instruments trace or frame-time measurement was performed.

The task checklists below retain the original acceptance scope. An unchecked runtime/test item is not implied to pass by this implementation record.

## Task 1 — Capture behavior and establish measurement seams

**Inspect:** `SidebarView.swift`, its Loading/SectionState/BranchActions/DragDrop extensions, all `Sidebar*Section`, `Sidebar*Row`, and context-menu files, `BranchRowContent`, `SidebarSelection`, `GitDragDropPolicy`, `GitDragPayloadStore`, and MainWindow action wiring. Read the native lists from PR #54 as implementation references rather than copying their assumptions wholesale.

- [ ] Inventory each row kind's click, double-click, context menu, embedded control, keyboard, drag source, and drop target behavior. Record existing action policy/helper names and disabled conditions in a parity test matrix.
- [ ] Inspect shared uses of `BranchNode`, `BranchRowItem`, tree builder, and drag overlays before changing their types or deleting them.
- [ ] Add `SidebarSignpost` and opt-in counters for snapshot build/apply, cell creation/configuration, menu build, selection dispatch, and payload processing. Keep instrumentation content-free and low overhead.
- [ ] Add `scripts/make-sidebar-perf-fixture.sh`: explicit temporary output directory, local refs only, 100/1,000/10,000 sizes, nested and flat cases. Refuse to overwrite an existing repository. Do not switch the user's open repository automatically.
- [ ] Record baseline if an app is already available for review. Otherwise mark baseline pending and proceed with deterministic implementation work; do not launch the app.

**Exit:** Complete behavior inventory and reproducible fixture/counter definitions. No unsupported claims about which path dominates runtime.

## Task 2 — Stable row identity and semantic selection mapping

**Modify:** `Sidebar/BranchNode.swift`, `Sidebar/BranchRowItem.swift`, `SidebarTreeBuilder.swift` and affected callers/tests.  
**Create:** `Sidebar/Native/SidebarRowID.swift`, `SidebarRowModel.swift` (proposed names).

- [ ] Replace random tree identity with typed stable identity, distinct for folder/leaf, ref namespace, section, and repository. Ensure intermediate callers compile during migration.
- [ ] Define row presentation values separately from identity and callbacks; implement explicit mapping to/from `SidebarSelection`.
- [ ] Inspect `StashEntry`, worktree and subtree models; ensure identity survives reorder while action locators are resolved from current records. Add object identity to native client data only if required for safe stash matching.
- [ ] Extend `SidebarTreeBuilderTests` and add `SidebarRowIdentityTests`: equal rebuild, insertion, rename, folder/leaf same path, same names across namespaces, repository switch, and shifting stash refs.

**Exit:** Equal source records produce equal IDs; content changes remain visible; no selection can alias another namespace/entity.

## Task 3 — Presentation store, snapshot invalidation, and load ordering

**Modify:** `SidebarView.swift`, `SidebarView+Loading.swift`, `SidebarView+SectionState.swift`, `SidebarView+BranchActions.swift`, relevant section loaders.  
**Create:** `Sidebar/Native/SidebarPresentationStore.swift`, `SidebarSnapshot.swift`, `SidebarSnapshotBuilder.swift`.

- [ ] Move section presentation data/derived caches into a narrow main-actor store, preserving existing Git-service calls and notification semantics. Keep sheets and operation coordination in their current owners.
- [ ] Build per-section trees/visible arrays and sorted menu indexes only on dependency changes. Publish coherent value snapshots; closures and transient drag state do not form part of equality.
- [ ] Assign generation before asynchronous work; reject obsolete repository/section results. Coalesce equivalent in-flight requests and preserve explicit forced-refresh semantics.
- [ ] Move large pure transformations off-main using immutable input if needed; cancel or ignore obsolete transformations. Do not add per-row tasks.
- [ ] Add `SidebarSnapshotTests` and `SidebarLoadingTests`: no rebuild for selection/hover/chrome, content-only badge update, expand invalidation, equal refresh, old request finishing last, repository switch during load, remote-menu-only update, and loading/error completion.

**Exit:** No tree building/filtering/sorting remains on the frequent SwiftUI body or pointer-event path. New source data reliably invalidates the relevant cache.

## Task 4 — Native table, reusable cells, and incremental reconciliation

**Decision:** Complete the agreed native cutover. Keeping the existing `List` did not resolve the reported long-list lag. Remove its production rendering path once all sections are represented in the shared table; retain runtime measurement as acceptance evidence, not as a gate that cancels the authorized implementation.

**Create:** `Sidebar/Native/SidebarNativeList.swift`, `SidebarTableView.swift`, native cell types, and `SidebarNativeListTests.swift`.

- [ ] Implement one native scroll/table pair with a flattened row datasource. Start with branch header/folders/leaves/detached HEAD and synthetic other row kinds; do not ship a partially migrated production sidebar.
- [ ] Create native labels/icons/badges/controls with reusable identifiers. No SwiftUI hosting or per-row native interaction overlay for dynamic leaves.
- [ ] Implement ID-index maps and deterministic structural operations; update only changed content rows. Equal snapshots are a no-op. Full reload is limited to initial install/repository reset.
- [ ] Capture/restore top visible ID plus pixel offset around structural or row-height updates. Preserve logical selection independently from visible selection when a folder collapses.
- [ ] Keep native coordinator delegates, observers, menu targets, and pending work correctly scoped and released at dismantle.
- [ ] Verify offscreen: equal update no-op, one badge update, insertion/deletion/reorder, anchor fallback, selected row removed/hidden, cell reuse reset, style/width changes, and callback suppression during external selection.

**Exit:** Stable native list lifecycle and deterministic incremental update behavior; no full refresh for selection or hover.

## Task 5 — Immediate selection and one activation path

**Modify:** native table/cell event routing, `SidebarView` selection bridge, existing section-action adapters.  
**Create:** `SidebarInteractionTests.swift`.

- [ ] Select and paint on primary mouse-down before forwarding the existing semantic selection callback. Guard duplicate selection/filter writes; do not delay native highlight for History loading.
- [ ] Implement double-click activation once on eligible release, cancel it after drag threshold, and maintain current-branch restrictions.
- [ ] Route folder/header toggles and embedded controls separately with real hit areas; remove reliance on the 96 pt current-branch passthrough.
- [ ] Preserve arrow navigation, focus, type-to-select, disclosure navigation and accessibility actions without adding destructive shortcuts.
- [ ] Test single/double-click callback counts, current branch, drag cancellation, inline controls, repeated selection, external selection, and hidden/removed IDs.

**Exit:** One event owner; zero menu/tree work during selection; selection publishes once per semantic change.

## Task 6 — Shared context-menu factory and current-target dispatch

**Inspect/replace:** branch/folder/tag/remote/worktree menus and menus embedded in stash/submodule/subtree/workspace rows.  
**Create:** `Sidebar/Native/SidebarMenuController.swift`, typed menu action/model files as needed, `SidebarMenuTests.swift`.

- [ ] Build the menu on right-click for the hit-tested ID, independent of navigation selection. Keep blank-space creation/visibility actions.
- [ ] Preserve every inventoried action's label, order and eligibility; route through existing action callbacks and policies.
- [ ] Reuse remote-data indexes and lazily populate large tracking submenus. Do not allocate menu trees while rendering cells.
- [ ] Keep only the open menu's targets alive; release on close/dismantle. Resolve item/repository at invocation and reject stale identities rather than act on recycled rows or shifted stash indexes.
- [ ] Test unselected clicked target, blank space, all menu inventories, current-branch restrictions, missing remotes/upstream, lazy submenu population, stale/deleted/renamed target, repository switch, and target release.

**Exit:** Zero menu builds on scroll/selection/refresh; one active menu tree; preserved action policy.

## Task 7 — Central native drag/drop session

**Modify:** native table, `SidebarView+DragDrop.swift`, adapters to existing drag policy/store.  
**Replace after parity:** row uses of `SidebarBranchDragSource`, `SidebarBranchDropTarget`, SwiftUI `.onDrag`/`.onDrop`.  
**Create:** `Sidebar/Native/SidebarDragSession.swift`, `SidebarDragSessionTests.swift`.

- [ ] Fix threshold ordering while migrating: no payload/state write before 4 pt; create/encode once on drag start.
- [ ] Own drag state outside cells and SwiftUI row snapshots. Preserve existing transferable payload format and cross-window store behavior.
- [ ] Decode incoming payload once per pasteboard revision/session; revalidate policy for target/modifier changes and again at drop.
- [ ] Update only affected hover rows/header; handle Option changes, native edge auto-scroll, commit-preview point size, and source-cell recycling/removal.
- [ ] Route accepted requests through existing confirmation/operation/undo handlers. Preserve all existing rejected-drop behavior and avoid duplicate drop execution.
- [ ] Test threshold jitter, single encode/decode, same-target updates, modifier changes, every policy target class, cross-repository rejection, cancellation, failed encoding, stale source/target, and cleanup exactly once.

**Exit:** No snapshot rebuild from drag movement; no duplicated native/SwiftUI target path; payload interoperability retained.

## Task 8 — Complete section parity and switch the sidebar

**Modify:** `SidebarView.sidebarList`, all section adapters, native row/cell models; retain surrounding presentation modifiers.

- [ ] Implement Workspace/Git Flow, Worktrees, Tags, Remotes, Stashes, Submodules, and Subtrees against the same table and menu/event system.
- [ ] Preserve loading/empty states, optional-section settings, persisted section expansion, badges, tooltips, current-branch controls, and all header actions/popovers.
- [ ] Bridge existing sheets/alerts through parent callbacks; a row disappearing while a sheet is open must not change that sheet's target.
- [ ] Add parity coverage for native snapshot output and each section's dispatch, including `SidebarViewStashTests`, branch badge tests, and existing submodule/subtree policy tests.
- [ ] Replace the production SwiftUI List once all sections are represented. Keep the existing sidebar chrome/account/update surface outside the native list.
- [ ] Check accessibility labels/actions, text scale, appearance and narrow geometry using offscreen validation where possible; record runtime visual checks separately.

**Exit:** All sections use one table and scroll owner with no missing actions or duplicate selection owner.

## Task 9 — Remove obsolete paths and validate

- [ ] Search call sites before deleting unused SwiftUI row/section/menu renderers and per-row overlays. Retain shared policies/content used elsewhere; remove adapters left solely for migration.
- [ ] Verify observers, cancellable loads, menu references and drag-store cleanup on repository switch/window close. Review final diff for accidental fetch, credential, Firebase, or Git-mutation changes.
- [ ] Build first using the repository command below. Run relevant non-emulator tests sequentially if the user permits test execution; the current instruction is build-only, so otherwise record tests as not run. Never retry a Firebase/XCTest bootstrap crash.
- [ ] Run `rtk git diff --check` and review the complete changed-file list.
- [ ] On an already available running app, execute the spec's behavior/performance matrix and record before/after results. Do not launch or relaunch automatically. If unavailable, leave runtime acceptance explicitly pending.

```bash
rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
rtk git diff --check
```

Relevant coverage to compile and, when permitted, execute: `SidebarTreeBuilderTests`, `SidebarViewStashTests`, `SidebarBranchSyncBadgeResolverTests`, `SubmoduleTreeTests`, `SubmoduleSidebarPolicyTests`, `SubtreeSidebarPolicyTests`, `GitDragDropPolicyTests`, plus the new identity/snapshot/loading/native-list/interaction/menu/drag suites. Use temporary repositories for integration coverage; no Firebase Emulator.

## Final acceptance record

Fill this in when implementation finishes; never convert unchecked runtime criteria into a build-based success claim.

| Area | Required evidence | Current status |
| --- | --- | --- |
| Behavior parity | Complete section/action matrix and dispatch coverage | All section callbacks/menu policies ported; runtime parity pending |
| Compilation | Successful macOS build | Passed |
| Deterministic correctness | Identity, stale loads, reconciliation, selection, menu and drag checks | Regression tests added; test target compilation blocked by existing actor/protocol errors |
| Scroll/selection/menu/drag latency | Release trace and spec budgets on documented hardware | Pending |
| Visual/keyboard/accessibility parity | Existing running app review across sizes/styles | Pending |
| Resource lifetime | Bounded reuse/retention after repeated cycles | Pending |
| Repository hygiene | Diff check, dead-code review, no unintended service changes | Passed |

The final handoff distinguishes implemented code, compilation evidence, tests actually executed, and runtime checks still pending. It does not commit, push, or deploy automatically.
