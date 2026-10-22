# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.20

Changes since `v1.1.19`.

### Added

- **Groq provider** — Use Llama and GPT-OSS models hosted on Groq with your own API key.
- **Thinking setting** — One toggle in Settings → AI Providers controls model reasoning for every configured cloud provider.
- **Branch pull requests** — Right-click a branch to view its pull request in a dedicated window, or create one when none is open. Works with GitHub and GitLab.
- **Repository action audit** — Review the Git commands that changed a repository during the session, with origin, status, and redacted output, in the Audit tab of the activity popover.
- **Repository Summary** — Repository details add a Summary tab with recent branches, tags, and commits alongside README and Statistics.
- **About Commit+** — A new About window, plus Help menu links to social updates, the issue tracker, and the website.
- A welcome sheet appears after signing in to a new account.
- Delete all app notifications at once.

### Improved

- Commit and pull request editors use separate title and description fields, and AI generates pull request titles and descriptions together.
- Settings use a toolbar layout, with list-detail Git provider accounts, a dedicated AI provider configuration sheet, and a custom action detail editor.
- **Open in Editor** opens files at the first changed line when the editor supports it.
- Branch rows show a worktree indicator, and selecting a worktree reveals its history.
- Undo, Open in, Settings, and AI actions share a single toolbar group.
- File Status reuses diffs of unchanged files and asks for confirmation before discarding changes.
- Interactive rebase shows inline progress and blocks other repository actions while it runs.
- Repositories default to the `origin` remote, and linked worktrees inherit the main worktree's default remote.
- The appearance setting now applies to pull request, comparison, and other AppKit windows.
- Automatic fetch runs every 30 seconds and recovers cleanly from cancellation.

### Fixed

- Commit+ Cloud sync of settings, bookmarks, custom actions, Git Flow configuration, commit rules, and provider accounts requires Pro and respects the settings-sync toggle.
- Staging a renamed file keeps the staged rename.
- Unstaged moves appear as a deletion and a new file, matching `git status`.
- Interactive rebase actions are available for commits brought in by merges.
- Claude repository-agent turns keep tools and thinking consistent across tool use.

[Compare v1.1.19 to v1.1.20](https://github.com/Commit-Plus/commit-plus/compare/v1.1.19...v1.1.20)
