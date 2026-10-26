# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.22

Changes since `v1.1.21`.

### Added

- **Notification settings** — Choose in Settings → Notifications whether pull request results and new app notifications show macOS banners, and optionally skip banners while Commit+ is the active app. New app notifications, such as merged-branch cleanup reminders, now also appear as macOS notifications; clicking one opens it in Commit+.
- **Credential helper fallback** — When a remote rejects your connected provider account over HTTPS, Commit+ retries with your own Git credential helpers, such as the GitHub CLI or macOS Keychain. Turn it off with **Fall back to Git credential helpers** in Settings → Git. Access errors now explain what was tried and how to grant a GitHub organization access to Commit+.

### Improved

- Deleting branches from the Delete Branches sheet runs in Background Activity, so the window stays usable.
- The account menu's Connections item is now **Git Provider Accounts…** and opens Settings → Git at the provider accounts section.
- Connecting an account in the add account sheet confirms the connection and shows when a token is saved.
- Jira issue filters show icons and highlight active filters.

### Fixed

- Adding, editing, or removing a remote in Repository Settings updates the sidebar and branch menus immediately.
- The add account sheet can no longer be saved while browser authorization is still pending.

[Compare v1.1.21 to v1.1.22](https://github.com/Commit-Plus/commit-plus/compare/v1.1.21...v1.1.22)
