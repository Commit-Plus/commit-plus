# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.15

Changes since `v1.1.14`.

### Added

- **Diff settings** — Customize the fixed-width font, text size, added and removed line colors, background opacity, and syntax highlighting, with Light and Dark previews and account settings sync.
- **Remote branch cleanup** — Optionally delete the tracked or matching remote branch when deleting local branches, from the sidebar or branch manager.

### Improved

- **Pull request creation** — Create pull requests in a dedicated resizable window without first loading the pull request list.
- **Stash details** — Show the stash description, branch, and creation time, keep a file selected, and display progress while its diff loads.
- **Branch navigation** — Highlight folders containing the current branch and load branch-specific history when its tip is outside the loaded history page.

### Fixed

- Diff panels now relayout when the window or split view is resized.
- Sidebar branch lists refresh after undo and redo, and branch selection receives keyboard focus.
- Stash diff loading ignores results for files that are no longer selected.
- Default diff text colors adapt to Dark appearance.

[Compare v1.1.14 to v1.1.15](https://github.com/Commit-Plus/commit-plus/compare/v1.1.14...v1.1.15)
