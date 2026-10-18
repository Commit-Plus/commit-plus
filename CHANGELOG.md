# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.18

Changes since `v1.1.17`.

### Added

- **Merged branch detection** — Commit+ Pro can mark local branches whose current tip was included in a merged GitHub pull request or GitLab merge request, show the provider evidence, and safely clean up confirmed branches after revalidation.

### Improved

- Selecting a branch while viewing all History now loads older pages until its tip is found instead of switching to a branch-only filter.
- Repository rows respond reliably to a single click for details and a double-click to open the repository.

### Fixed

- Opening a repository with uncommitted changes from Welcome now goes directly to File Status.

[Compare v1.1.17 to v1.1.18](https://github.com/Commit-Plus/commit-plus/compare/v1.1.17...v1.1.18)
