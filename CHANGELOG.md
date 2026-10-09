# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.12

Changes since `v1.1.11`.

### Added

- **GitHub notifications** — Check repository notifications from the toolbar, refresh them on demand, and open related GitHub activity from the new popover.
- **Command-line tool setup** — Install the `commit` command from the app menu or Settings with clearer setup guidance.

### Improved

- **Faster History and diff browsing** — New native table-backed views, incremental loading, cached graph geometry, and cancellable detail loading reduce unnecessary work while navigating large repositories.
- **Settings organization** — App, repository, account, and connection settings are easier to navigate, with account and connection management consolidated in Settings.
- **Push workflow** — The branch push sheet has a clearer, more compact layout.

### Fixed

- Diff content in detail panels now scrolls reliably and no longer conflicts with split-view divider hit testing.
- History detail loading resumes cleanly after interruption and avoids stale work when selection changes.
- The GitHub notification account picker no longer truncates when the popover uses a fixed height.
- Repository menu actions target the correct window more reliably.

[Compare v1.1.11 to v1.1.12](https://github.com/Commit-Plus/commit-plus/compare/v1.1.11...v1.1.12)
