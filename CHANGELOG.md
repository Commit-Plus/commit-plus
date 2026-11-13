# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.26

Changes since `v1.1.25`.

### Added

- **File Blame and History windows** — Right-click a file in a commit's changes or in the revision browser and choose **Blame…** or **History…**. Blame shows who last changed each line, and lets you step to older or newer revisions of the file. History lists the commits that changed the file and follows renames.
- **More file actions at a revision** — The same file menu adds **Save As…** to save the file as it was at that revision, plus **Show in Finder**, **Show in File Tree**, and **Copy Path**.
- **Tabs in the History details panel** — The details panel now has **Commit**, **Changes**, and **File Tree** tabs. **Commit** shows the full message and author, and you can click a parent commit to jump to it. **File Tree** shows the repository at that commit. You can also collapse the panel to its tab bar, or open the revision in a new window.

### Improved

- **Faster file previews** — File previews and the revision tree now scroll smoothly in large files and repositories. Folders use the standard macOS folder icon.

### Fixed

- **History refresh** — History now refreshes after local commits, message-only amends, empty commits, and resets, including ones made in a terminal.
- **Scanning repository folders** — When a repository folder is itself a Git repository, scanning it now also finds the repositories nested inside it.

[Compare v1.1.25 to v1.1.26](https://github.com/Commit-Plus/commit-plus/compare/v1.1.25...v1.1.26)
