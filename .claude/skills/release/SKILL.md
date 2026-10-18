---
name: release
description: Release Commit+ macOS from main by synchronizing required Firebase rules, bumping marketing version, writing the latest changelog, assessing and updating feature documentation and Firebase announcements, building, committing, pushing a version tag with release notes, and stopping after remote tag verification. Use when the user invokes /release or explicitly asks to release this app.
argument-hint: "[version | patch | minor | major]"
disable-model-invocation: true
---

# Release Commit+

Work in the macgit repository root (this project). Follow its current AGENTS.md (and CLAUDE.md if present) 

`rtk` is an optional local tool. Before running commands, check `command -v rtk`: if it is available, prefix commands with `rtk` (`rtk proxy` where no dedicated wrapper exists); otherwise run the same commands directly without the prefix. Commands below are written without `rtk`.

## User-authorized release policy

Invoking this skill to perform a release authorizes the full workflow: update version and changelog, build, commit directly on `main`, push `main` and the release tag to the configured remote, and prepare release notes for GitHub Release. Completion means the tag was pushed successfully and verified on the remote. The user handles the release pipeline and publication afterward; do not watch, poll, wait for CI, verify release assets/appcast, or schedule background monitoring (no `Monitor`, `ScheduleWakeup`, `/loop`, cron, or background shell jobs). The user explicitly requested direct commits on `main` for releases as an exception to the repository's no-direct-main-commit rule. Do not create a release branch or ask for redundant confirmation of these actions. Creating/editing this skill or discussing releases does not itself authorize executing a release.

Invoking this skill also authorizes the smallest production Firestore rules deployment required by the release's native Firebase contract. Before preparing the app release, compare any changed document paths, encoded fields and types, queries, and authorization assumptions with the owning source in `../landing-page`. When the release adds or changes a Firestore contract and the matching rules source is present, inspect the exact rules diff and configured project, then run a non-interactive rules-only deployment to project `macgit` before building or tagging. Do not ask for separate confirmation for this required rules-only deployment. Never broaden it to Functions, indexes, provisioned documents, or other Firebase targets. If the matching source is absent, the configured project is ambiguous, the rules file contains unrelated unpublished behavior that cannot be separated safely, or deployment fails, stop before releasing and report the blocker.

Release execution also includes assessing documentation in `../docs-page` and the landing-page announcement stored in Firebase. When warranted, update feature documentation locally and update only the release-related announcement data in production project `macgit`; this authorization does not extend to unrelated Firebase data or deployments. Preserve each sibling repository's instructions and unrelated changes. The direct-main commit/push exception above applies only to `macgit`; do not infer permission to commit, push, or deploy the sibling websites. Editing this skill does not itself authorize any release, documentation publication, or production announcement write.

Default to the next patch version (`1.1.3` becomes `1.1.4`). Honor an explicit version or minor/major bump, including one passed as the skill argument (`$ARGUMENTS`). Marketing version is `X.Y.Z`; tag is `vX.Y.Z`, required by the existing release CI. Do not change `CURRENT_PROJECT_VERSION`; CI supplies its build number.

## Prepare from current evidence

1. Inspect status, branch, remotes, current marketing versions, `CHANGELOG.md`, `scripts/release/prepare-release.sh`, `.github/workflows/release-app-update.yml`, and the release runbook if present. Check GitHub authentication/access. Do not execute the preparation script blindly: it can commit and push before building.
2. Inspect the release range for native Firebase contract changes. If present, inspect `../landing-page/AGENTS.md`, status, `firestore.rules`, matching tests, `.firebaserc`, and `firebase.json`. Confirm the rules diff contains the matching allowlist/type checks and no unrelated unpublished rules behavior, then deploy only Firestore rules with `firebase deploy --only firestore:rules --project macgit --non-interactive`. Require explicit CLI success and report source/deployment state separately. Do not run Firebase Emulator tests.
3. Fetch the release remote's main branch and tags without force. Use the configured GitHub release remote; resolve ambiguity before publication. Start from clean `main`. If another branch is checked out and clean, switch to existing main without discarding changes. Fast-forward main when it is only behind. Inspect local commits ahead of remote because they will be included in the release. Stop on divergence, dirty files, or unrelated staged changes; do not stash, reset, or silently include them. Ask only for the missing decision needed to resolve that state (use `AskUserQuestion`).
4. Resolve the previous stable release tag reachable from the intended release HEAD, checking semantic versions and ancestry rather than tag dates alone. Inspect newer remote stable releases too; stop if the chosen base would release an older/divergent line unintentionally. Ensure all marketing versions agree and the target version is newer than both the current marketing version and the previous release. Ensure the target tag is absent locally and remotely and no GitHub Release already uses it. On an interrupted retry, inspect existing commit/tag/release state and resume the same release instead of incrementing again or overwriting a tag.
5. Read both `git log <previous-tag>..HEAD` and `git diff <previous-tag> HEAD`. Inspect relevant implementation changes to substantiate each release-note entry. If there is no previous tag, explicitly use the first-release scope. Do not invent changes or relabel old Unreleased notes. If no releasable changes exist, report that and stop unless the user explicitly requests a version-only release.

## Feature documentation and announcement assessment

Perform both assessments for every release after reviewing the previous-tag range and before committing/tagging. Record the decision and reason even when no update is needed.

### Documentation in docs-page

- Inspect `../docs-page` instructions, status, `docs.json`, and relevant existing feature pages. For a new user-facing feature, write or extend its documentation unless the current docs already cover the released behavior accurately. Also update instructions affected by changed workflows; fixes that do not change usage normally need no feature-doc edit.
- Explain the actual UI entry point, steps, options, and relevant limitations using the native implementation as evidence. Reuse existing pages and style, add navigation only for a new page, and verify internal links. A changelog entry alone does not replace feature documentation. Add a versioned changelog page when consistent with the site's conventions, using only the verified release range.
- Review the focused diff and run available documentation checks. Report local edits separately from committed, pushed, or published docs. Do not claim that new docs URLs are live merely because their source exists.

### Landing-page announcement via Firebase

- Decide whether this release warrants a banner: a meaningful new feature, substantial user-facing improvement, or important fix usually does; routine maintenance and minor fixes usually do not. Do not replace a still-relevant campaign just to increment the version.
- Inspect the current implementation and live configuration before deciding. The current contract is `websiteConfig/announcements` in project `macgit`, consumed by `app/api/announcements/route.ts`, validated by `lib/announcement-config.ts`, and rendered by `components/announcement-banner.tsx`. Rediscover these if the contract changes. The existing `scripts/seed-announcements.mjs` only creates an absent document and is not an update command.
- When warranted, prepare concise desktop/mobile copy and a useful HTTPS or internal link. Use a unique release ID such as `vX.Y.Z`; preserve unrelated entries and fields. The API selects the first enabled entry, so ensure the intended banner is selected without silently removing unrelated campaigns. Validate `id`, `enable`, `message`, `mobileMessage`, `linkLabel`, and `href` against the actual schema.
- Use the existing authenticated admin path or Firebase Admin tooling, keep credentials out of output, confirm project `macgit`, and apply a transaction that preserves concurrent/unrelated data and follows the existing audit-log convention. Read the document back and verify the selected announcement; verify the public announcement API when accessible. Report production data updates separately from source commits and Firestore rules deployment.
- Do not announce availability while the release pipeline is unverified or link to unpublished documentation. If publication is needed first, prepare the exact payload and report the banner update as a remaining publication step for the user; do not monitor CI or schedule a later write. If credentials or a safe update path are missing, report that limitation rather than claim the banner is updated.

## Version, notes, and build

1. Update every `MARKETING_VERSION` entry in `macgit.xcodeproj/project.pbxproj` to the target version (currently four entries; discover rather than assume the count).
2. Replace `CHANGELOG.md` with only the new release's changes since the immediately preceding release. Use appropriate user-facing headings such as Added, Improved, and Fixed; omit empty categories and repository maintenance presented as app features. Preserve the established language/style. Include the new version and an exact previous/current tag comparison link using the actual GitHub repository. Do not retain older release sections or Unreleased.
3. Prepare a temporary UTF-8 notes file containing that release's meaningful changelog body and comparison link. Use it for the annotated tag and retain the same content in CHANGELOG.md so the user can use it as the GitHub Release description. Keep the temporary file outside the repository and pass its path rather than shell-interpolating multiline text. Tag annotations do not automatically set a GitHub Release body; leave GitHub Release creation/editing to the pipeline or user, and do not wait for a release to exist.
4. Review the full diff and run `git diff --check`, then:

   ```sh
   xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
   ```

   Build only; do not launch/relaunch the app. Verify effective build settings and the produced app's `CFBundleShortVersionString` agree with the target version. Match exact setting keys when resolving `BUILT_PRODUCTS_DIR` and `FULL_PRODUCT_NAME`. Stop on build failure or version mismatch; do not commit/tag/push a failed preparation. Documentation/version-only edits do not require a test run, but release preparation always requires this build.

## Commit and publish

1. Recheck branch, reviewed diff, and staged paths. Stage only the release version and changelog files. Commit on `main` with `chore: release vX.Y.Z` (append any commit attribution trailer the session requires). Verify the resulting commit contains the reviewed changes; save its SHA and ensure HEAD has not changed before tagging.
2. Push `main` without force. If rejected, stop and resolve the remote changes; rebuild/review the resulting release commit before proceeding. Create an annotated `vX.Y.Z` tag at the saved latest release commit, using the notes file as its annotation, and push only this tag. Never force-push or move an existing release tag. Verify remote main and the peeled remote tag resolve to the intended commit.
3. Stop after successful push and remote tag verification. Do not run `gh run watch`, poll Actions, wait for release creation, edit the release after CI, verify ZIP/DMG/appcast, or create a monitoring automation, scheduled wakeup, or background task. The user will handle and watch the approximately 15-minute pipeline.
4. Report version, previous tag, release commit SHA, build outcome, successful remote tag verification, and a workflow page link for the user. Include the documentation and announcement decisions, any changed paths, their local/published/deployed state, and remaining publication steps. Point to CHANGELOG.md for the prepared description. State that pipeline monitoring and final publication are handed off to the user; do not claim CI success, published assets, or runtime UI validation.
