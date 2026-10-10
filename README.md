<p align="center">
  <img src=".github/assets/logo.png" width="128" height="128" alt="Commit+">
</p>

<p align="center">
  <h1 align="center">Commit+</h1>
</p>

<p align="center">
  A fast, native Git client for macOS.<br>
  Free and open source.
</p>

<p align="center">
  <a href="https://github.com/Commit-Plus/commit-plus/releases/latest"><img src="https://img.shields.io/github/v/release/Commit-Plus/commit-plus?label=release" alt="Latest release"></a>
  <a href="https://github.com/Commit-Plus/commit-plus/releases/latest"><img src="https://img.shields.io/badge/Swift-5.0-orange" alt="Swift"></a>
  <a href="https://img.shields.io/badge/macOS-26.2%2B-blue"><img src="https://img.shields.io/badge/macOS-26.2%2B-blue" alt="macOS"></a>
  <a href="https://www.gnu.org/licenses/agpl-3.0"><img src="https://img.shields.io/badge/License-AGPL_v3-blue.svg" alt="License: AGPL v3"></a>
</p>

<p align="center">
  <a href="https://commitplus.app/" target="_blank">Website</a> •
  <a href="https://github.com/Commit-Plus/commit-plus/releases/latest" target="_blank">Download</a> •
  <a href="https://docs.commitplus.app/" target="_blank">Documentation</a>
</p>

<p align="center">
  <a href="https://tools.cafe" target="_blank" rel="noopener">
    <img src="https://tools.cafe/b/light.svg" alt="Featured on tools.cafe" width="256" height="80" />
  </a>
</p>

---

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/dark-commit-plus.png">
    <source media="(prefers-color-scheme: light)" srcset=".github/assets/commit-plus.png">
    <img alt="Commit+ Git client for macOS" src=".github/assets/commit-plus.png" width="800">
  </picture>
</p>

Commit+ is a native macOS Git client built with Swift and SwiftUI — designed to be fast, lightweight, and deeply integrated with the platform. Optional account features add settings sync, provider integrations, and AI-assisted workflows.

## Features

### Revision Browser & Visual Comparisons

- **Browse any revision**: Explore its complete file and folder tree without checking it out, with text, image, and Git LFS previews.
- **Compare files and folders**: Compare a path in your working tree or a revision against any commit, branch, or tag.
- **Compare branches**: Inspect changed files, unique commits, merge bases, and ahead/behind counts using merge-base or tip-to-tip comparisons.

### Selective Apply & Revert

Bring back only the changes you need from any commit — or reverse them — by file, hunk, or selected lines. Commit+ previews the patch, detects stale state, and provides visual conflict resolution when changes do not apply cleanly.

### Git LFS

Set up Git LFS, manage tracking rules, find and convert large files, inspect local object availability, and download missing content with progress and cancellation. Commit+ can use System Git LFS or manage its own private runtime, including LFS-aware clone and revision previews.

### Drag & Drop Workflows

Stage and unstage files, apply stashes, reorder or squash commits, cherry-pick or revert across branches, merge or rebase branches, and publish or pull branches with direct manipulation.

### Safe, Complete Git Management

- **Everyday Git**: Commit, fetch, pull, push, branch, merge, rebase, stash, cherry-pick, revert, reset, tags, and reflog.
- **Undo & redo**: Recover from staging, commits, stashes, discards, branch operations, and supported remote actions.
- **Conflict resolution**: Review inline conflicts, choose resolutions, stage the result, or continue/skip/abort interrupted operations.
- **Worktrees & submodules**: Create and manage worktrees, plus add, initialize, update, synchronize, edit, and remove submodules from the sidebar.
- **Pull requests**: Create pull requests for GitHub, GitLab, and Bitbucket repositories, with in-app review for GitHub and GitLab.

### Git Flow

Set up and run feature, bugfix, release, and hotfix flows without an external `git-flow` installation. Start topics in the current repository or a new worktree, finish with merge or rebase strategies, and recover interrupted flows.

### AI-Assisted Git

Generate editable Conventional Commit messages with Apple Intelligence or your own OpenAI, Gemini, Claude, DeepSeek, or OpenRouter key. Repository AI can inspect repository context and route supported actions through Commit+'s existing safety and confirmation flows.

### Search & Terminal Integration

Quick Search finds commits, files, branches, and tags from one place. The optional `commit` CLI opens a repository in Commit+ from Terminal:

```sh
commit                  # Open the current folder's repository
commit .                # Same behavior
commit "/path/to/repo"   # Open a specific repository
commit --help
```

Install it from **Settings → General → Command Line**. The command opens the repository; it does not create a Git commit. Subfolders and linked worktrees are supported.

## System Requirements

- **macOS**: 26.2+
- **Xcode**: 26.2+ (to build from source)
- **Git**: Installed on the system (Homebrew or Xcode Command Line Tools)

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, coding conventions, and pull request guidelines, and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

For security issues, please refer to [SECURITY.md](SECURITY.md).

## License

This project is licensed under the [GNU Affero General Public License v3.0 (AGPLv3)](LICENSE).

For GitHub Enterprise Server and GitLab Self-Managed setup, see [Self-hosted Git providers](docs/self-hosted-git-providers.md).
