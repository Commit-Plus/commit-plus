# Commit+ (macgit)

Native macOS Git client built with Swift and SwiftUI, with AppKit integration where needed. Requires macOS 26.2+ and Xcode 26.2+. Git runs through `Process()` subprocesses.

See `README.md` for features and `CONTRIBUTING.md` for setup and coding conventions.

## Working Style

- Work directly on clear tasks. Keep changes focused and preserve existing behavior outside the requested scope.
- Do not create specs, plans, or roadmaps unless the user asks. Existing documents in `docs/` are reference material, not required workflow steps.
- Inspect the current implementation before changing behavior; follow existing patterns instead of adding parallel abstractions.
- Preserve unrelated local changes. Do not automatically stash, reset, commit, or push.
- When a new branch is needed, use `codex/<topic>`. Do not commit directly to `main`.
- Use `rtk` for shell commands; use `rtk proxy <command>` for commands without a dedicated wrapper.

## Project Layout

- `macgit/App/`: app lifecycle, shared state, feature controllers, and menu/toolbar wiring.
- `macgit/Views/`: SwiftUI screens and reusable UI, grouped by feature; `MainWindow` coordinates repository actions.
- `macgit/Services/`: Git execution, undo, AI providers/tools, account integrations, and persistence.
- `macgit/Models/` and `macgit/ViewModels/`: data types and presentation state.
- `macgit/Resources/`: assets and bundled resources.
- `macgitTests/`: XCTest coverage, including integration tests using temporary Git repositories.
- `command-line/`: the `commit` CLI that opens repositories in Commit+.
- `scripts/`: CLI build/tests and release tooling; `.github/workflows/`: CI and release automation.

## Firebase Ownership

- Firebase backend logic has moved to the sibling `../landing-page` repository. Make changes to Firestore rules, Cloud Functions, backend tests, and feature-policy provisioning scripts there, following that repository's `AGENTS.md`.
- Do not recreate or maintain Firebase backend logic in `macgit`. This repository owns only native Firebase client integration, local policy fallbacks, and app-side access checks.
- For plan/feature changes, inspect the feature policy in `../landing-page` and keep its configuration aligned with the native client when needed. Distinguish local changes from deployed Firebase changes; do not claim deployment without verification.
- Do not run Firebase Emulator or emulator-backed tests, including through wrapper scripts. Use source review, syntax checks, and relevant builds; report emulator tests as not run.
- Native client configuration is documented in `docs/firebase-setup.md`.

## Implementation Rules

- Keep views focused on presentation and callbacks. Put coordination in the existing controllers/view models and Git execution in `GitStatusService*.swift`.
- Follow existing concurrency and state-management patterns. Keep blocking Git work off the main thread and UI state updates on the main actor.
- Reuse existing menu/toolbar notification routing and respect the target repository/window.
- After mutations, follow the existing `SyncState` refresh and repository-notification flow. Preserve selection and viewport during background refreshes.
- Register undo only after an action succeeds. Validate expected state before destructive undo/redo and refresh repository state afterward.
- Route Repository AI actions through the existing tools, policies, and coordinators. Preserve confirmation and revalidation for mutations; keep credentials out of model context and logs.
- Keep secrets in the existing local credential stores and Keychain. Do not add credentials or machine-specific paths to synced configuration.
- Preserve existing copyright and license notices. New Swift files may use `// SPDX-License-Identifier: AGPL-3.0-or-later` or the full AGPL header; no specific author name or email is required. The pre-commit license check is advisory.

## Release Changelog

- A release changelog must describe only changes introduced since the immediately preceding release tag. Identify that tag and inspect both `git log <previous-tag>..<release-ref>` and `git diff <previous-tag> <release-ref>` before writing release notes; use the intended release commit as `<release-ref>` before tagging.
- Verify each changelog entry against that range. Do not simply rename `Unreleased`, carry forward old entries, or describe existing features as newly released. An `Unreleased` section may be stale or contain changes already shipped.
- `CHANGELOG.md` contains only the latest release's changes compared with the immediately preceding release. Replace its contents for each release; do not retain older release sections or an `Unreleased` section. This file is not a release history archive.
- Group user-facing changes under appropriate headings and link the exact previous/current tag comparison. Omit empty categories and avoid presenting repository maintenance as app functionality.
- Update the marketing version and changelog, review the diff, and complete the required build before committing, tagging, and pushing a release. Inspect release scripts before invoking them because they may commit and push immediately.
- If correcting notes after publication, do not move or force-push the existing release tag. Report separately whether the correction is local, committed, or published.

## Validation

For app code changes, build without launching the app:

```bash
rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

For non-trivial logic changes, run relevant XCTest coverage; narrow the scope with `-only-testing:macgitTests/<TestClass>`:

```bash
rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitUndoCommitIntegrationTests test
```

- Run builds and tests sequentially to avoid Xcode build database locks.
- Do not launch or relaunch the app to verify changes. If tests crash during bootstrapping (`Early unexpected exit` / `abort() called`, including Firebase initialization), do not retry; report the limitation and use a successful build as compilation evidence.
- A successful build does not verify runtime UI behavior. State clearly when interaction has not been checked.
- For CLI changes, run `rtk proxy bash scripts/test-command-line.sh`.
- For documentation-only changes, review the diff; no app build is needed.
- Run `rtk git diff --check` before handing off changes, and summarize validation and any remaining limitations.
