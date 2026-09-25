# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.6

Changes since `v1.1.5`.

Read more about Revision file and commit feature at our blog: https://commitplus.app/blog/browse-and-compare-git-revisions
### Fixed

- Allow Git hooks and filters to find Git LFS installed in common package-manager locations when Commit+ is opened from Finder.
- Default Pull to the current branch's upstream remote and branch, and show sync activity on the local branch being updated.
- Refresh repository state after a failed pull so merge conflicts appear in File Status, and include Git's detailed failure output in error messages.
- Show in-progress merges in File Status with Continue and Abort actions, including merges with no remaining file changes, and keep File Status visible when opening a repository with an unfinished operation.

[Compare v1.1.5 to v1.1.6](https://github.com/Commit-Plus/commit-plus/compare/v1.1.5...v1.1.6)
