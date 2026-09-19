# Changelog

All notable changes to Commit+ are documented here.

## Unreleased

Changes since `v1.1.1`.

### Added

- **Welcome Dashboard** — A new local-first dashboard summarizes recent repositories, commit activity over the last 30 days, active days, and repositories that need attention. It also provides quick access to repositories with uncommitted work, ahead/behind branches, missing folders, and recent activity without automatically fetching or uploading repository data.
- **Commit+ AI for Pro** — Commit+ Pro users now receive **500 AI credits every month** for managed AI features, including commit-message generation and Repository AI. No API key or model configuration is required. Settings show the available balance and next renewal date; unused credits expire at the end of each monthly period.

### Improved

- Expanded submodule management with nested folder presentation, folder expand/collapse controls, clearer names and paths, accessibility labels, a detail placeholder, and additional sidebar actions.
- Added a force option when re-adding submodules and improved forced removal, with explicit safety checks for dirty worktrees, staged changes, nested paths, and stale `.git/modules` directories.
- Added support for choosing and validating local Git repositories when adding subtrees, including local `file` transport handling and clearer validation for existing destination folders.
- Refined the recent-repository list so branch, changed-file, ahead, and behind status load independently and appear sooner.
- Added sidebar controls for showing or hiding submodules and subtrees.
- Improved Settings presentation so it opens in the correct repository window.
- Added automated macOS build and unit-test checks, with more deterministic offline test execution.
- Updated project links, release-feed configuration, and product artwork.

### Fixed

- Fixed Push selecting the wrong remote in repositories with multiple remotes; it now prefers the current branch's upstream remote.
- Fixed Commit+ AI backend configuration and reduced unnecessary allowance requests with a five-minute usage cache.
- Fixed submodule removal when the submodule was newly added or had staged changes, while preserving explicit force confirmation for destructive cases.
- Fixed submodule add failures caused by empty destination folders, nested submodule paths, or stale internal Git directories by validating them before running Git.
- Fixed local subtree add and pull operations failing because Git's local `file` transport was not enabled.
- Fixed repository picker status rows showing incomplete or misleading values while background metadata was still loading.

[Compare changes since v1.1.1](https://github.com/Commit-Plus/commit-plus/compare/v1.1.1...main)
