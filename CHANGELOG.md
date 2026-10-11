# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.14

Changes since `v1.1.13`.

### Added

- **Tag toolbar button** — Create tags from the repository toolbar, with visibility controls in Appearance settings and the View menu.
- **Git Flow cleanup options** — Choose whether to delete the local branch and remove its local worktree after a successful Finish. Worktree cleanup checks that it is clean, unlocked, and unchanged before removal.

### Improved

- **Git LFS browsing** — View a storage overview, file details, local content state, and recent author and commit metadata, with controls that adapt to the available width.
- **Git LFS tracking rules** — Distinguish wildcard patterns from exact filenames and remove rules directly from the list.
- **Account sign-in** — A refreshed login layout adapts to its content, and Forgot Password opens the password reset flow on the web.
- **Repository layout** — Minimum window and sidebar widths account for the selected text size.

### Fixed

- Removing an exact Git LFS tracking rule preserves other wildcard rules and unrelated attributes.
- Git LFS downloads select the tracked remote when available, then fall back to origin or another available remote.
- Sidebar badges reserve enough space to avoid clipping text edges.

[Compare v1.1.13 to v1.1.14](https://github.com/Commit-Plus/commit-plus/compare/v1.1.13...v1.1.14)
