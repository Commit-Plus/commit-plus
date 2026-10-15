# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.16

Changes since `v1.1.15`.

### Added

- **Tree file lists** — Switch between plain lists and folder trees in Staged, Changed, History, and pull request file lists. Select or stage and unstage whole folders in File Status.
- **Image comparison** — Compare before and after images side by side or with a draggable overlay in File Status and History.
- **Git Flow labels** — Choose full names, first letters, or hidden sidebar branch-role labels in Repository Settings.

### Improved

- Repository dialogs show loading progress during preparation and keep operation errors available for retry.
- Background refresh avoids redundant History reloads and file line-count loading, keeping repository views more responsive.
- Pull request lists and details display cached content while refreshing expired data.
- Refreshed the app icon and Git Flow branch badges.

### Fixed

- Stale pull request list caches no longer skip refreshes.
- Branch-name sanitization handles invalid Git ref characters and reserved names.
- Branch selection and History filtering follow the checked-out branch after checkout.

[Compare v1.1.15 to v1.1.16](https://github.com/Commit-Plus/commit-plus/compare/v1.1.15...v1.1.16)
