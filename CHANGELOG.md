# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.9

Changes since `v1.1.8`.

### Added

- **Configurable credential helpers** — Choose a fallback Git credential helper in Settings while Commit+ connected accounts remain the first choice, with safeguards for existing helper chains and insecure stores.
- **GitLab token recovery** — GitLab accounts now refresh expiring OAuth tokens automatically and clearly prompt for reauthorization when required.
- **Account email visibility** — View the signed-in account email from the toolbar menu and Manage Account sheet.

### Improved

- **Faster History browsing** — Large histories load and scroll more efficiently with incremental commit graph generation and bounded page retention.
- **Faster repository status loading** — The repository picker consolidates status checks, and the sidebar batches branch synchronization lookups.
- **More consistent repository windows** — Opening a repository from the welcome window preserves its initial frame and presentation context.

### Fixed

- Command-line setup now recognizes an existing Commit+ CLI symlink after the app moves or updates.

[Compare v1.1.8 to v1.1.9](https://github.com/Commit-Plus/commit-plus/compare/v1.1.8...v1.1.9)
