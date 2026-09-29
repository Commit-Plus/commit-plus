# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.8

Changes since `v1.1.7`.

### Added

- **Drag-and-drop staging** — Stage or unstage one or multiple selected files by dragging them between File Status sections, with Shift and Command selection support.
- **Customizable repository sidebar** — Choose whether Tags, Worktrees, Reflog, Pull Requests, Git LFS, and Git Flow appear in the sidebar. These preferences participate in settings sync.

### Improved

- **Dedicated Settings window** — Settings now opens in its own resizable macOS window instead of a sheet attached to a repository window.
- **Faster repository and diff presentation** — Repository details no longer wait for icon loading, while diffs display plain text sooner and cache deferred syntax highlighting.
- **Cleaner commit dragging** — Dragging commits from History now shows one preview with the selected commit count.

### Fixed

- Discard and undo snapshots now work correctly in linked Git worktrees.
- The command-line setup tip waits until the terms have been accepted.
- Repository toolbar button labels no longer clip on macOS 27.

[Compare v1.1.7 to v1.1.8](https://github.com/Commit-Plus/commit-plus/compare/v1.1.7...v1.1.8)
