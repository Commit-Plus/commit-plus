# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.4

Changes since `v1.1.3`.

### Added

- Visual branch comparison workflow: compare any two branches, tags, or commits with a dedicated comparison view showing commits, file changes, and diffs.
- Protected branch commit warnings: when attempting to commit to a protected branch, a confirmation sheet explains the protection and offers to create a new branch instead.
- SQLite-backed LocalDataStore with async operations: migrated repository bookmarks, provider accounts, commit rules, GitFlow configuration, and visibility cache to a local SQLite database for better performance and reliability.

### Improved

- Conflict resolution UI: refined the merge tool layout, line highlights, and synchronized scrolling for a clearer side-by-side comparison.
- Lazy loading for large files and batched diff rendering: improved responsiveness when viewing large files or many changes in History and File Status.
- Sidebar scroll behavior: scroll indicators now appear only when needed, and keyboard-driven scrolling is smoother.
- Welcome page activity cache: cache entries are now keyed by date for more accurate daily activity tracking.
- GitFlow sync and related controllers refactored to use the new async LocalDataStore, simplifying synchronization logic.

### Fixed

- Branch rename sheet now initializes with the current branch name.
- Right-click context menus on commit rows in History now appear correctly.
- Drag-and-drop commit reordering with preview no longer misplaces commits during the drag.
- Sync data setting persistence and migration from legacy storage.

[Compare v1.1.3 to v1.1.4](https://github.com/Commit-Plus/commit-plus/compare/v1.1.3...v1.1.4)