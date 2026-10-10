# Repository Screen Cache — Design Spec

**Date:** 2026-10-10
**Status:** Approved direction; implementation pending.
**Scope:** File status, History, and Reflog within an open repository window.
**Plan:** [Implementation plan](../plans/2026-10-10-repository-screen-cache-plan.md)

## Problem and current implementation

Switching screens currently removes the previous branch of `MainWindowView.detailPane`. Screen-owned state is recreated when returning:

- `HistoryScreen` owns `HistoryListModel` and `HistoryCommitDetailModel`. The list model's bounded snapshot cache therefore does not survive screen removal. Cache hits also currently rebuild the graph. `HistoryCommitTableController` uses incremental insertion for pagination but `reloadData()` for refresh.
- `FileStatusView` owns status, selection, diff, and supplementary data in local state. Its appearance task calls `loadStatus()`, which waits for several Git queries before publishing the file list.
- `ReflogView` owns `ReflogViewModel`; its appearance task loads with `reset: true`.

The user observes approximately 1–2 seconds of loading after navigation. This duration is user-reported, not an instrumented baseline.

## Behavior contract

1. Initial entry may show initial loading. Returning to a loaded screen presents its last successful snapshot without waiting for Git.
2. Invalidation marks data stale; it does not clear visible rows, selection, details, or viewport.
3. File status always revalidates in the background on activation. History and Reflog revalidate on activation when stale, or immediately when invalidated while active.
4. Hidden screens retain state and receive invalidation, but do not start new refreshes. An already-running load may finish and populate its cache.
5. Equal results cause no row publication or table reload. Changed results preserve surviving selection and viewport. Explicit branch/filter navigation retains its intentional reset behavior.
6. Refresh failure preserves the last successful snapshot, exposes the error, and leaves the model stale for retry. Empty success is distinct from never loaded or failed.
7. Closing the repository session releases models, observers, snapshots, and tasks. Worktrees have distinct working-directory identities. Separate windows do not share selection or scroll state.
8. Existing Git execution, mutation confirmation, undo, fetch cadence, and repository refresh routing remain authoritative. This feature does not change Firebase contracts.

## Ownership and state

Introduce a repository-session screen store owned at the stable repository/window level, outside `detailPane`'s switch. It lazily owns the three screen models and routes activation and invalidation. Reuse existing History and Reflog models; extract File status loading and presentation data into a dedicated model. Views retain transient presentation state such as open sheets and invoke existing action coordinators.

Retain History list/detail state, query/filter context, loaded depth, selection, and viewport anchor. Retain File status snapshot, selected file identity, selected diff and file-list viewport. Retain Reflog entries, filter, selection, loaded depth and viewport. Store viewport by stable row identity plus pixel offset where the native surface permits it; if an anchor disappears, use a deterministic surviving neighbor and clamp to valid bounds.

Cache keys include repository identity and every query input affecting results. History includes branch/ref filter, remote inclusion, search and other load-policy inputs. Reflog includes reference mode; File status distinguishes staged and working-tree diff identities. Mutable dependencies such as preferred remote and Git Flow configuration must be updated rather than captured permanently at model creation.

Reuse `BoundedMemoryCache` and the existing History capacity of three query snapshots. Cache complete reusable History presentation data, including graph output and refs metadata, keyed by its input revision. Keep only the active File status snapshot and selected diff, and one active Reflog query snapshot with its loaded pages. Do not persist cache to disk or accumulate a diff for every visited file. Loaded pagination may grow while in use; alternate-query caches must have a documented row/cost budget as well as entry limits. Eviction must not blank an active screen. Honor the existing clear-session-caches action by evicting reusable snapshots and invalidating active data.

## Invalidation and freshness

Observe existing repository notifications at the session level, so changes are not lost while a screen is absent. Add typed affected-data information only where useful; notifications without that information conservatively invalidate all three screens. Audit actual operation completion paths before adding notifications to avoid duplicate refreshes.

| Trigger | Required effect |
|---|---|
| Fetch or push | Invalidate History, including refs/labels, and Reflog; refresh File status integration metadata |
| Commit, amend, checkout, pull, merge, rebase, reset, cherry-pick, revert, undo/redo | Conservatively invalidate all affected snapshots |
| Stage, unstage, discard, working-tree edits | Refresh File status and selected diff; other screens only when their source data can change |
| Branch/tag/ref, stash or worktree operations | Invalidate affected refs/history/reflog and working-tree state; unknown scope falls back to all |
| App activation, existing local refresh and manual refresh | Route through session freshness handling; preserve existing fetch behavior |
| Clear session caches | Evict reusable cache, mark data stale, refresh active screen |

Successful operations invalidate after completion. Failed operations that may partially mutate Git state must also reconcile through existing refresh/error paths. Changing files outside the app must continue to be detected through current refresh mechanisms; do not infer an unchanged working tree solely from unchanged status letters or HEAD.

Each data domain tracks an invalidation generation and last successfully applied generation. A load captures its repository/query key and generation. Apply results only for the matching key and current generation. Invalidation during a load remains pending and schedules one follow-up if active; it must not be erased by completion of the older request. Coalesce overlapping requests per domain and avoid unbounded retry loops on failure. Cancellation must clear loading state without marking data fresh. Navigation between repositories must never publish a previous repository's result.

## Screen-specific updates

### File status

Publish cached data immediately on activation, then read fresh status off the main actor. Publish the core list before slower optional metadata where dependencies permit. Compare meaningful values before assignment; update line counts, LFS flags and integration metadata independently. Preserve file identity using path and staged/unstaged context, including rename information already available in the app.

Always revalidate the selected diff when working-tree freshness is checked. A file can change contents without changing its status, size, or number of diff lines. Compare actual diff content/revisions, not just status membership or timestamps. Preserve existing diff identity/rendering behavior and selection safeguards; do not duplicate its caches. If the selected file disappears, use the current selection policy rather than displaying an unrelated stale diff.

### History

Reuse rows and graph immediately on return. Refresh the previously loaded range, so an older selected commit does not disappear merely because only page one was fetched. Compare commit identity/order, displayed metadata, refs, graph and pagination state; matching commit hashes alone do not imply unchanged rendering.

Extend the native table's change representation to support safe insertions/removals and row-content updates. Graph changes can affect existing rows and must be included in the update set. Maintain the pagination/loading sentinel correctly. Use a full reload with viewport restoration for complex reorderings, incompatible base revisions or ambiguous changes. Do not optimistically insert a guessed commit or assume fetch always prepends history.

Retain the viewport anchor in the model/session, not just in the native controller, because the table can be destroyed during navigation. Capture before teardown and restore after rows/layout are ready without overriding a subsequent user scroll. Preserve selection callbacks and suspend/resume detail behavior; hidden screens must not remain command targets.

### Reflog

Separate initial/query-reset loading from background refresh. Refresh preserves the loaded range and surviving selection. Use the existing entry identity and equality semantics after verifying their stability across rereads; commit hash alone is insufficient because multiple reflog entries can reference the same commit. Do not clear entries on ordinary activation or invalidation.

## Acceptance and validation

- Repeated File status → History → Reflog navigation shows prior data before any new Git result; fresh History/Reflog activation starts no data reload.
- Each relevant operation invalidates hidden screens and updates active screens without blanking them. Push-only ref changes update History labels.
- Equal refreshes cause no History row revision/reload and no replacement of equal File status/Reflog collections.
- Selection, loaded depth and scroll survive navigation and background refresh; missing anchors and deleted selections degrade predictably.
- An edit preserving `modified` status and diff line count still updates the selected diff.
- In-flight invalidation, cancellation, failures, rapid filter changes and repository switching never publish stale or cross-repository results.
- Session teardown releases observers/tasks; cache entry/cost limits are exercised.

Implement deterministic tests for freshness transitions, result ordering, snapshot comparison and table change classification. Build first and run permitted relevant tests sequentially under repository instructions. For this task the user requests build-only app validation and no relaunch; record interactive checks as pending rather than claiming runtime proof. Never retry Firebase bootstrap crashes. Documentation creation itself requires diff review only, not an app build.

## Non-goals

No disk cache, global shared screen state, new polling timer, speculative Git mutation UI, whole-app navigation rewrite, or caching of additional screens in this iteration.
