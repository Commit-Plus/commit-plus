# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.17

Changes since `v1.1.16`.

### Added

- **Interactive rebase** — Right-click a History commit to reorder commits, reword messages, edit, squash, fixup, or drop eligible commits. Review commit details and changes before rebasing, and continue, skip, or abort paused rebases from File Status.
- **Repository catalog and details** — Discover local repositories from selected folders in Your Repos, browse plain or folder-tree lists, and use View to inspect repository information, remotes, and the working-tree README without opening a workspace.
- **Repository statistics** — Explore commit activity by month, contributor, weekday, and hour with date-range controls and locally cached results.
- **Pull request notifications** — Receive macOS notifications when pull request creation succeeds or fails; click a notification to open the repository’s Pull Requests view.

### Improved

- The Push dialog offers a Force Push option for one selected branch, with a separate review flow and tags excluded.
- Repository pickers and the Welcome dashboard avoid redundant background updates, with clearer loading and Push dialog layouts.
- Conflict resolution uses native code panes with synchronized scrolling.

### Fixed

- Canceling or closing the commit editor cancels pending AI commit-message generation and prevents late results from replacing the message.
- GitHub notifications marked Done stay completed across refreshes until new activity arrives.

[Compare v1.1.16 to v1.1.17](https://github.com/Commit-Plus/commit-plus/compare/v1.1.16...v1.1.17)
