# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.27

Changes since `v1.1.26`.

### Improved

- **Automatic rescans of repository folders** — Your Repos now rescans a folder automatically when repositories are added, renamed, moved, or deleted inside it, so the list stays current without a manual refresh.
- **Deeper repository scanning** — Scanning now finds repositories nested inside other repositories, up to four folder levels below each added folder. It skips `node_modules` and submodules, and a single unreadable item no longer stops the whole scan.

### Fixed

- **Removing folders from Recent** — In the Recent folder tree, Control-click any folder and choose **Remove from Recents** to remove every repository inside it, including ones that were renamed or deleted. Before, the menu was often empty or removed the folder from Your Repos instead.
- **Delete All notifications** — **Delete All** in the Notifications panel now asks for confirmation inside the panel and deletes the notifications. Before, the panel closed and nothing was deleted.
- **Create Tag sheet** — The Create Tag sheet no longer opens empty, and it starts with a cleared tag name each time.

[Compare v1.1.26 to v1.1.27](https://github.com/Commit-Plus/commit-plus/compare/v1.1.26...v1.1.27)
