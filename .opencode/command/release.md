---
name: release
description: Release Commit+ macOS from main by bumping marketing version, writing the latest changelog, building, committing, pushing a version tag, and publishing verified GitHub release notes. Use when the user invokes $release or asks to release this app.
---

# Release Commit+

Work in `/Users/thanhtran/Project/Commit+/macgit`. Follow its current AGENTS.md and use `rtk` for commands (`rtk proxy` where no wrapper exists).

## User-authorized release policy

Invoking this skill to perform a release authorizes the full workflow: update version and changelog, build, commit directly on `main`, push `main` and the release tag to the configured remote, and publish the GitHub Release description. The user explicitly requested direct commits on `main` for releases as an exception to the repository's no-direct-main-commit rule. Do not create a release branch or ask for redundant confirmation of these actions. Creating/editing this skill or discussing releases does not itself authorize executing a release.

Default to the next patch version (`1.1.3` becomes `1.1.4`). Honor an explicit version or minor/major bump. Marketing version is `X.Y.Z`; tag is `vX.Y.Z`, required by the existing release CI. Do not change `CURRENT_PROJECT_VERSION`; CI supplies its build number.

## Prepare from current evidence

1. Inspect status, branch, remotes, current marketing versions, `CHANGELOG.md`, `scripts/release/prepare-release.sh`, `.github/workflows/release-app-update.yml`, and the release runbook if present. Check GitHub authentication/access. Do not execute the preparation script blindly: it can commit and push before building.
2. Fetch the release remote's main branch and tags without force. Use the configured GitHub release remote; resolve ambiguity before publication. Start from clean `main`. If another branch is checked out and clean, switch to existing main without discarding changes. Fast-forward main when it is only behind. Inspect local commits ahead of remote because they will be included in the release. Stop on divergence, dirty files, or unrelated staged changes; do not stash, reset, or silently include them. Ask only for the missing decision needed to resolve that state.
3. Resolve the previous stable release tag reachable from the intended release HEAD, checking semantic versions and ancestry rather than tag dates alone. Inspect newer remote stable releases too; stop if the chosen base would release an older/divergent line unintentionally. Ensure all marketing versions agree and the target version is newer than both the current marketing version and the previous release. Ensure the target tag is absent locally and remotely and no GitHub Release already uses it. On an interrupted retry, inspect existing commit/tag/release/run state and resume the same release instead of incrementing again or overwriting a tag.
4. Read both `git log <previous-tag>..HEAD` and `git diff <previous-tag> HEAD`. Inspect relevant implementation changes to substantiate each release-note entry. If there is no previous tag, explicitly use the first-release scope. Do not invent changes or relabel old Unreleased notes. If no releasable changes exist, report that and stop unless the user explicitly requests a version-only release.

## Version, notes, and build

1. Update every `MARKETING_VERSION` entry in `macgit.xcodeproj/project.pbxproj` to the target version (currently four entries; discover rather than assume the count).
2. Replace `CHANGELOG.md` with only the new release's changes since the immediately preceding release. Use appropriate user-facing headings such as Added, Improved, and Fixed; omit empty categories and repository maintenance presented as app features. Preserve the established language/style. Include the new version and an exact previous/current tag comparison link using the actual GitHub repository. Do not retain older release sections or Unreleased.
3. Prepare a temporary UTF-8 notes file containing that release's meaningful changelog body and comparison link. Use this exact description for GitHub Release, not GitHub's generated notes. Keep the temporary file outside the repository and use `--notes-file` rather than shell interpolation of multiline text.
4. Review the full diff and run `rtk git diff --check`, then:

   ```sh
   rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
   ```

   Build only; do not launch/relaunch the app. Verify effective build settings and the produced app's `CFBundleShortVersionString` agree with the target version. Match exact setting keys when resolving `BUILT_PRODUCTS_DIR` and `FULL_PRODUCT_NAME`. Stop on build failure or version mismatch; do not commit/tag/push a failed preparation. Documentation/version-only edits do not require a test run, but release preparation always requires this build.

## Commit and publish

1. Recheck branch, reviewed diff, and staged paths. Stage only the release version and changelog files. Commit on `main` with `chore: release vX.Y.Z`. Verify the resulting commit contains the reviewed changes; save its SHA and ensure HEAD has not changed before tagging.
2. Push `main` without force. If rejected, stop and resolve the remote changes; rebuild/review the resulting release commit before proceeding. Create an annotated `vX.Y.Z` tag at the saved latest release commit, using the notes file as its annotation, and push only this tag. Never force-push or move an existing release tag. Verify remote main and the peeled remote tag resolve to the intended commit.
3. The tag triggers `release-app-update.yml`, which builds/signs/notarizes, publishes ZIP/DMG, and deploys the Sparkle appcast. Inspect its current publication behavior to avoid competing creation. With the current workflow, let CI create the GitHub Release; then set its description using `gh release edit <tag> --repo <owner/repo> --notes-file <notes-file>`. If CI no longer creates releases, create one with `--verify-tag --notes-file` only after the required artifacts are ready. Do not publish an empty release as a substitute for failed CI.
4. **Stop after pushing the tag.** Do not monitor or wait for the CI pipeline (it takes ~15 minutes). The user will manually monitor the workflow and handle any follow-up. Report the version, previous tag, release commit SHA, build outcome, and links to the GitHub Actions workflow and expected GitHub Release.