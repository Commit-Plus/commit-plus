# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.21

Changes since `v1.1.20`.

### Added

- **Jira issues** — Connect a Jira Cloud site in Settings → Integrations to see the issues assigned to you in the sidebar's Workspace section, filter them by sprint, status, project, and type, and start a branch or Git Flow topic from an issue. Requires Pro.
- **ChatGPT provider** — Sign in with a ChatGPT Plus or Pro plan instead of an API key.
- **ChatGPT (Codex) provider** — An unofficial connection that signs in with any ChatGPT account, including Free, to use its Codex usage.
- **GitHub Copilot provider** — Sign in with GitHub to use your Copilot plan, including Copilot Free, and choose from the models it includes.
- **Azure Repos** — Connect Azure DevOps organizations with a personal access token over HTTPS or SSH, discover their repositories, and list, review, and merge pull requests.
- **Browser sign-in for GitHub and GitLab** — Connect GitHub.com and GitLab.com accounts through OAuth in the browser, or with a personal access token.
- **Branch cleanup banner** — A repository banner offers to delete branches that are fully merged.
- Creating a branch can commit all changes right away.
- Push and Fetch toolbar buttons show a badge while those operations run in the background.

### Improved

- Merges prefill the commit subject and description from Git's merge message, without comment lines such as the conflicts list.
- File lists show file-type icons with status badges, and row heights scale with text size.
- The in-progress merge, rebase, and similar operation banner appears in the main window.
- Git provider accounts moved to Settings → Git.
- Update prompts include the release notes.
- Identical pending push and fetch requests are no longer queued twice.

### Fixed

- Reconnecting a Git provider account no longer creates a duplicate, and adding an account that is already connected is rejected.
- Testing an SSH key on an HTTPS account keeps that account's saved token and identity.
- The File Status list stays at the top when new rows are inserted above.
- Git Flow start errors appear in the start sheet.
- Running an older build no longer makes release notes appear again.

[Compare v1.1.20 to v1.1.21](https://github.com/Commit-Plus/commit-plus/compare/v1.1.20...v1.1.21)
