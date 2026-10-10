# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.13

Changes since `v1.1.12`.

### Added

- **View release notes again** — Open the changelog for your installed version from the GitHub notifications popover.

### Improved

- **Diff browsing** — Canvas-backed rendering, cached text layout, and stable line identities reduce rendering work for large diffs and long lines.
- **Native sidebar and file lists** — AppKit tables handle sidebar navigation, changed files, and commit files with reusable rows and native click and drag handling.
- **Repository screen switching** — File Status, History, and Reflog retain their screen state when switching views and defer refresh work while inactive.
- **Branch names** — Creating and renaming branches preserves capitalization and non-whitespace characters, while replacing whitespace with hyphens.

### Fixed

- Fetch uses the current branch's tracked remote, falling back to origin or an available remote, without resolving credentials for unrelated remotes.
- Fetching all remotes continues after an individual failure, retains successful updates, and reports failures by remote.
- Release notes match the installed app version instead of loading the latest changelog from main.

[Compare v1.1.12 to v1.1.13](https://github.com/Commit-Plus/commit-plus/compare/v1.1.12...v1.1.13)
