# Repository catalog, detail and statistics

## Implementation status

- Implemented local SQLite catalog collections, atomic legacy import, per-root membership reconciliation, stable IDs/relinking and persisted provider identities. Legacy defaults remain intact for recovery.
- Both picker tabs now use the same native hosted list and existing row actions/badges. View opens a separate detail panel in Welcome and New Tab.
- Detail uses native grouped Form sections, matching App Settings: Repository, Remotes, README and separate statistics/chart blocks.
- Statistics are lazy and cached locally with deterministic query keys, a six-hour TTL, explicit Reload bypass and bounded retention. Scope is all local refs plus HEAD, counting shared commits once, including merges, with raw author-email identity.
- Validation: macOS app build and standalone production-source SQLite/Git integration checks passed. Re-run checks with `rtk proxy bash scripts/test-repository-catalog.sh`.
- Runtime layout/interaction review remains pending because the app was not launched or relaunched.

## Agreed behavior

- Recent and Your Repos share the same list renderer, row presentation and controls in Welcome and Choose a Repository.
- Plain/tree, sort, provider/star filters and expansion state remain global local settings. Do not add these to Firebase settings.
- Tree follows the actual path hierarchy, merges shared ancestors and shows child folders before direct repositories.
- Your Repos supports multiple selected folders, rejects Home and filesystem root, reports duplicate selections, and deduplicates repositories found under overlapping roots.
- Preserve existing open, clone, link, repair, remove-from-recents and bookmark actions.
- Add View on repository rows. View selects the repository and shows its detail in the right panel; Open continues opening the repository workspace.
- Detail contains repository information, Summary (README) and Statistics with a date-range control.
- Branch, changed count and ahead/behind stay in memory and refresh from Git through the existing flow. Do not persist them in SQLite.

## 1. Local persistence and identity

Reuse `LocalDataStore` and its actor-isolated `LocalSQLiteDatabase`, shared transaction queue and migration infrastructure. The current database stores Codable payloads in named collections, so the initial implementation can add collections without introducing another database or ORM. Add typed SQL tables/indexes later only if measured query needs justify them.

| Collection | Persisted data |
| --- | --- |
| repositoryCatalog | Stable local UUID, canonical worktree path, display name, provider/remotes metadata, last seen, availability |
| repositoryScanRoots | Root UUID, canonical path, added time, latest scan outcome |
| repositoryRootMemberships | Root ID and repository ID, one record per unique pair |
| repositoryRecents | Repository ID and last opened time; retain the current 20-entry limit |
| repositoryStatisticsCache | Repository ID, cache version, query options, history fingerprint, calculated time and aggregate series |

- Canonicalize and deduplicate paths before assigning IDs. Local ID identifies one checkout/worktree, not a remote URL; two clones of the same remote remain separate local repositories.
- Moving a repository preserves its local ID only through a validated relink/update-folder action. Do not guess identity from matching names/remotes.
- Keep root membership separate: removing one scan root must preserve repositories belonging to another root, recents, or bookmarks.
- Folder tree nodes are derived from paths, not separately persisted catalog entities.
- Reuse existing synced bookmark identities and device-local path mappings. Resolve each local clone against the bookmark identity without silently overwriting another clone's mapping during scanning. Scanning never creates bookmarks or cloud writes.
- Do not persist credentials or credential-bearing remote URLs; reuse existing remote normalization/redaction before storing metadata.

## 2. Safe migration

1. Prepare the existing database and check a new migration marker dedicated to the repository catalog. Do not reuse the legacy defaults migration marker.
2. Import selected folders from `dev.thanhtran.macgit.yourRepositoryFolders` and entries from `dev.thanhtran.macgit.recentRepositories`.
3. Normalize paths, merge duplicates and preserve recent names, ordering and timestamps. Preserve unavailable recent repositories for the existing locate/remove flow.
4. Commit catalog, roots, memberships, recents and the marker atomically; verify imported records before switching reads/writes.
5. Leave old defaults intact for recovery, but stop writing them after a successful migration. If migration fails, keep the existing flow usable and report the storage error; never replace valid data with an empty catalog.
6. Scanned repositories were previously held only in RAM. Discover them on the first background scan and persist the result; do not pretend they were migrated from disk.

UI preferences stay in their existing local settings keys. Read and write expansion/provider filters through one shared settings owner so open windows observe changes immediately, including when all folders are collapsed.

## 3. Catalog loading and scanning

- Introduce one catalog owner shared across picker windows. Adapt RecentRepositoriesStore/YourRepositoriesStore to this owner rather than leaving independent authoritative lists.
- Load saved catalog snapshots first, then reconcile in the background. No directory enumeration, Git commands or database work in row body/render callbacks.
- Coalesce scans requested by multiple windows. Propagate cancellation to the worker and discard obsolete generations.
- Enumerate selected roots recursively; recognize `.git` directories and worktree `.git` files. Skip Git internals and avoid symlink loops; retain the existing stop-at-repository behavior initially.
- Resolve provider metadata independently of star status, preferring origin and falling back to recognized remotes. Keep the externaldrive fallback.
- Batch persistence and publish only changed results. Never clear a populated list just because a refresh starts.
- Track scan success per root. Permission errors, an unmounted volume or cancellation must not be treated as a complete empty scan or erase valid memberships.
- Remove stale memberships only after successful reconciliation of the corresponding root. Repositories still referenced by recents/bookmarks remain available for missing-folder handling.
- Refresh on explicit rescan, root changes and relevant repository notifications; debounce activation refreshes rather than launching concurrent full scans.

## 4. Shared list and selection

- Consolidate Recent and Your Repos into one reusable list with a common row model and callbacks. Keep existing badges, provider icons, stars, tooltips and context actions consistent.
- Use the existing native table reuse/update pattern for plain and tree presentations. Only reload changed rows; keep hover and scrolling inside the row/AppKit boundary.
- Build hierarchy once per relevant data/settings change. Filtering retains matching repositories' ancestors; expand/collapse operates on the actual hierarchy.
- Keep selected repository and viewport stable during background refresh, provider resolution and badge updates. Switching view mode preserves selection.
- View selects immediately and requests detail separately. Cancel the previous detail request and check repository ID/generation before publishing, preventing slow repo A results from replacing repo B.
- Provide the same right-panel behavior in Welcome and New Tab. Initially show the existing Welcome dashboard/no-selection content; offer a route back to it after viewing a repository.

## 5. Detail and Summary

- Header: repository name/path, availability, remotes/provider links, changed count, commit count, first/latest commit dates and repository size.
- Use existing GitStatusService entry points for Git execution and an existing/new detail coordinator for loading. Views remain presentation/callback-only.
- Load inexpensive metadata and README first. Commit totals and repository size load independently in the background; define size as the Git object database (loose objects and packs) in binary units. Exclude working files and build caches; linked worktrees use the common object database.
- Summary reads the working tree README directly, including uncommitted edits. Use case-insensitive README discovery with a deterministic preference for Markdown, then plain text; show an explicit empty state if absent.
- Reuse the installed MarkdownUI renderer, resolve relative links/images against the repository directory and keep file reading off the main actor. Bound rendering work for unusually large README files.
- Re-read README on relevant file/repository changes and activation while selected, not on every view render. No SQLite README cache is required initially.
- Empty repositories, missing folders, unavailable remotes and partial read failures have independent states; a failed metric must not blank the whole panel.

## 6. Statistics

- Compute lazily when Statistics is opened, only for the selected repository; keep prior results visible while refreshing the same query.
- Scope: commits reachable from all local refs and HEAD, with an explicit scope label; deduplicate by commit OID. Overview and Statistics use the same repository-wide scope.
- Define and retain consistent query options: date range, ref scope, merge inclusion, author identity/mailmap behavior, author timestamp and local display timezone. Use the same options for all charts and totals.
- First charts: commits by month (series by contributor), contributor totals/top contributors, commits by weekday and commits by hour. Use native Swift Charts; bound visible contributor series and group the remainder as Other.
- Read Git log once per calculation and derive all aggregates from that result. Cache aggregate datasets, not an unbounded copy of every commit.
- Cache key includes repository ID, schema/calculation version, date range, scope, merge/identity settings and timezone. Validity uses calculated time with a six-hour TTL. History fingerprints describe the calculated snapshot rather than invalidating it on each ref change.
- Statistics are an overview cached for six hours per repository/query. Git notifications do not invalidate the cache. Reload explicitly recomputes from local Git history; it does not fetch from remotes. Expired entries refresh when statistics are requested.
- Treat shallow history explicitly as partial local statistics. Empty repositories render zero/empty charts without errors.
- Bound cache size/retention; disposable statistics cache failures never block access to the catalog or repository.

## Delivery order

1. Catalog schema/models, repository-specific migration and shared persistence owner. Keep UI behavior intact.
2. Persisted scan reconciliation, provider metadata and membership handling; unify list/tree rendering and global settings observation.
3. View action, immediate selection, shared right-panel detail and README Summary.
4. Statistics loader, cache invalidation and charts/date controls.

Each stage should compile and preserve existing behavior before proceeding to the next. This document is the implementation plan; no migration or feature code is changed by writing it.

## Validation and acceptance

- Migration: fresh install, populated legacy defaults, duplicates/aliases, unavailable recents, interrupted/failed import and idempotent rerun. Verify old defaults are retained and original data survives failures.
- Catalog: overlapping roots, removing one root, worktrees, nested folder hierarchy, duplicate selection, Home/root rejection, permission errors, unavailable volumes and stale scan cancellation.
- UI: same row presentation/actions in both tabs and both picker locations; folder-first hierarchy; settings propagate across windows and survive restart; no Git/database work restarts during scroll.
- Detail: fast A-to-B selection, canceled reads, background refresh, unchanged-data updates, README edits and relative links, missing/large README and empty repositories.
- Statistics: known fixture histories, date/timezone boundaries, author identity, merge handling, ref changes, rewritten history, shallow clones and cache eviction/invalidation.
- Use isolated temporary databases/directories for tests; do not touch the user's catalog. Run focused tests when the test target can compile. Existing unrelated actor-isolation test failures must be reported separately.
- Run app builds and tests sequentially, then `rtk git diff --check`. Follow the user's build-only instruction: do not launch/relaunch the app; report runtime UI validation as pending.
- All catalog/settings/statistics work is local. Existing bookmark sync continues through its current contract; any future cloud contract change requires separate cross-repository assessment and authorization.
