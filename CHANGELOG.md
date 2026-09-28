# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.7

Changes since `v1.1.6`.

### Added

- **Git LFS support** — Full Git LFS integration with embedded runtime, tracking rules management, file downloads, and credential handling. LFS files are tracked, downloaded, and displayed in File Status with dedicated controls.
- **Selective apply and revert in History** — Apply or revert individual commits from History as patches, with conflict resolution UI for merge conflicts.

### Changed

- **Improved memory usage and app lifecycle** — Reduced memory footprint, faster cold starts, and better background/foreground handling.
- **Updated revision browser** — Enhanced revision browsing with image previews and improved file preview support.
- **Refined pull behavior** — Pull now defaults to the current branch's upstream; sync activity shows on the local branch being updated.
- **Merge conflict handling** — Repository state refreshes after a failed pull so conflicts appear in File Status; Git's detailed failure output is included in error messages.
- **In-progress merge visibility** — File Status shows in-progress merges with Continue and Abort actions, even when no file changes remain, and stays visible when opening a repository with an unfinished operation.

### Fixed

- Git hooks and filters can now find Git LFS installed in common package-manager locations when Commit+ is opened from Finder.
- Various stability fixes and UI polish across File Status, History, Diff View, and Settings.

[Compare v1.1.6 to v1.1.7](https://github.com/Commit-Plus/commit-plus/compare/v1.1.6...v1.1.7)
