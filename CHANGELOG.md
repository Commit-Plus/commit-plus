# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.3

Changes since `v1.1.2`.

### Improved

- Moved the History branch graph into its own resizable column and kept dense graphs within that column.
- Persisted History column widths so they scale with the window, retain their proportions when columns are hidden, and support horizontal scrolling when needed.
- Improved the repository picker with hover highlights, pointing-hand cursors on interactive controls, and an adaptive layout for Open, Clone, and Create Repository actions.

### Fixed

- Fixed History column resizing restoring stale widths during a drag or shrinking columns when the horizontal scrollbar appears.
- Preserved selected commits when loading another page of History and prevented delayed selection restoration from applying to a different history view.
- Fixed Push remote selection: prefer the current branch's upstream remote, then the repository's default remote; require an explicit choice when multiple remotes remain ambiguous.
- Cancelled outdated remote-loading tasks when switching the Push remote and prevented submission when pushing is unavailable.

[Compare v1.1.2 to v1.1.3](https://github.com/Commit-Plus/commit-plus/compare/v1.1.2...v1.1.3)
