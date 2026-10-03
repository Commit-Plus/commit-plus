# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.10

Changes since `v1.1.9`.

### Added

- **Self-hosted Git providers** — Pro users can connect GitHub Enterprise Server and GitLab Self-Managed accounts with personal access tokens, browse available repositories, and use their configured server for Git and pull request operations.
- **Adjustable app text size** — Choose Default, Large, or Extra Large text in Appearance settings, with the selection applied throughout the app and saved between launches.
- **Branch-only History filtering** — Show commits unique to the selected branch by choosing a comparison base, including local or remote branches.

### Improved

- **Clearer History graphs** — Expanded graph colors and larger reference labels make busy branch histories easier to read.
- **More reliable History navigation** — Selecting a branch now focuses its tip commit while preserving table focus, and column widths remain fixed when the window changes size.
- **Smoother branch drag and drop** — Sidebar branch dragging no longer triggers selection or double-click actions while a drag is in progress.

### Fixed

- History loads now discard stale results when branch filters or searches change quickly.
- The final History column width is now captured reliably when resizing ends.

[Compare v1.1.9 to v1.1.10](https://github.com/Commit-Plus/commit-plus/compare/v1.1.9...v1.1.10)
