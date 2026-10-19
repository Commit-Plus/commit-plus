# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.19

Changes since `v1.1.18`.

### Added

- **Background Git activity** — Push, fetch, and remote branch deletion run in the background. Click the repository name to review queued actions and error details.
- **App notifications** — Switch between GitHub and app notifications, view release notes, and open daily merged-branch cleanup reminders.
- **Repository recovery** — Locate a moved repository folder, retry access, or close an unavailable repository.

### Improved

- File Status shows separate staged and changed file counts in the sidebar.
- History caches commit details and file diffs for faster repeat navigation.
- Pull request descriptions and comments support richer Markdown and GitHub review diff context, with branch-name and link copy controls and a more adaptable header.
- Automatic fetch backs off after failures and coordinates with queued remote actions.

### Fixed

- Batch branch deletion continues after individual failures and reports the affected branches.
- Pull request notification clicks reuse an existing repository window when available.

[Compare v1.1.18 to v1.1.19](https://github.com/Commit-Plus/commit-plus/compare/v1.1.18...v1.1.19)
