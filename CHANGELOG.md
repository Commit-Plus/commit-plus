# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.23

Changes since `v1.1.22`.

### Added

- **Hosted issue trackers** — The repository sidebar has a new ISSUES section that shows **GitHub Issues**, **GitLab Issues**, **Bitbucket Issues**, or **Azure Boards** when one of the repository's remotes is on that provider. Browse and search issues, filter by state (Open, Closed, All) and by All, Assigned to Me, or Created by Me, and pick the remote when several have a tracker. The details pane shows the description, labels, assignees, and comments. Create issues, add comments, close or reopen issues, and start a branch from an issue. Free for public repositories; Pro for all repositories.
- **Redo button** — The repository toolbar now has a Redo button next to Undo.

### Improved

- Jira moved from the Workspace section to the new ISSUES section. Hide or show the whole section with **Show Issues** in Settings → General or the sidebar context menu; your existing Jira visibility setting carries over.
- Azure Repos remotes now offer an issues link that opens the project's Boards work items.
- Bitbucket accounts can save an optional Atlassian email, which Bitbucket Issues needs for API tokens. It stays on this Mac with the token.
- GitHub sign-in always lets you pick the account, and a connected GitHub account offers **Grant Organization Access on GitHub** to grant or request access to more organizations.

### Fixed

- Submodules with uncommitted changes only inside their own checkout no longer offer stage or discard actions that cannot work. Commit+ explains the state and offers **Open Submodule**.
- Creating a tag now refreshes the tag badges in the commit history.

[Compare v1.1.22 to v1.1.23](https://github.com/Commit-Plus/commit-plus/compare/v1.1.22...v1.1.23)
