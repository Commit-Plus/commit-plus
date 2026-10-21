# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The project rules (working style, Firebase ownership/deployment, implementation rules, release changelog, validation) live in `AGENTS.md` and apply here in full:

@AGENTS.md

## Commands

`rtk` is optional (see AGENTS.md); commands below are written without it.

```bash
# Build (Debug)
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build

# Single test class / single test method
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/<TestClass> test
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/<TestClass>/<testMethod> test

# CLI (`commit` command in command-line/) tests, outside Xcode
bash scripts/test-command-line.sh

# Standalone script tests (scripts/tests/*.swift)
bash scripts/test-interactive-rebase.sh
bash scripts/test-repository-catalog.sh

# Whitespace check before handoff
git diff --check
```

There is no separate linter. Shared git hooks are enabled with `git config core.hooksPath .githooks` (pre-commit: advisory AGPL header check; pre-push: release tag must match `MARKETING_VERSION`). The app requires `macgit/GoogleService-Info.plist`; CI generates it from repository variables.

Release work is driven by the project skill `/release` (`.claude/skills/release/SKILL.md`). Do not run `scripts/release/prepare-release.sh` blindly: it commits and pushes before building.

## Architecture

**Command routing.** Menu and toolbar commands do not call views directly. They go through `FocusedValues` (`ToolbarAction`, `RepositoryWindowCommandState`, etc.) and `NotificationCenter` notifications posted with the key window as `object` (`WindowScopedNotification.post`). Receivers must filter on their own window so commands hit only the target repository. `MainWindowView` is the coordinator for repository actions and is split into `MainWindowView+<Feature>.swift` extensions.

**Git execution.** All git work goes through `actor GitStatusService` (`GitStatusService.shared`), which spawns `Process()` and is split by feature into `GitStatusService+<Feature>.swift`. Use its `runGit`/`runGitBounded`/`runGitRaw` helpers rather than new process code; `GitCommandRunning` is the protocol seam for tests. The git binary itself is resolved by `GitRuntimeManager` (system git or a managed download), and Git LFS has its own runtime (`GitLFSRuntime`).

**Refresh after mutations.** `SyncState` owns repository refresh: `refresh(repositoryURL:force:)` coalesces local refreshes via an internal actor and uses a generation counter so stale results are dropped, plus throttled automatic fetches. Cross-view updates are broadcast with `.repositoryDidChange`, `.repositoryLocalStateDidRefresh`, `.repositoryRemoteRefsDidRefresh`, etc. (declared in `SyncState.swift`).

**Undo.** Undo is data-driven: actions are described as `GitUndoOperation` values (including precondition checks such as `requireHead`, `requireLocalBranchTip`, `requireCleanWorkingTree`) and executed by `GitUndoExecutor`. File-content undo uses snapshots (`GitFileUndoSnapshotStore`, `GitUndoSnapshotRegistry`). Branch/remote/stash helpers live in `Git*UndoSupport.swift`.

**Repository AI.** The chat agent (`RepositoryAIAgentHarness`) can only act through typed tools: read-only git commands (`RepositoryAIGitCommandPolicy`/`Executor`), local mutations (`RepositoryAIMutationPolicy`/`Executor`), and remote operations (`RepositoryAIRemoteOperationPolicy`/`Executor`). Each has a policy that gates what is allowed and requires user confirmation and revalidation for mutations. Commit-message generation is separate, with one provider per backend (`*CommitMessageProvider.swift`) registered in `AIProviderRegistry`; API keys are in `AIProviderCredentialStore` (Keychain).

**Accounts, plans, and cloud sync.** Firebase Auth/Firestore are client-only here. Feature gating goes through `FeatureAccessResolver` with `FeaturePolicyStore`/`FeaturePolicyCache` (local fallback) and entitlements (`FirestoreEntitlementStore`, `EntitlementCache`). Synced settings are encoded by `CloudSettingsDocument` (see AGENTS.md before adding fields). Other synced data (bookmarks, custom actions, Git Flow config, commit rules) follows a `*CloudStore` + `Firestore*Store` pair; local persistence uses SQLite (`LocalSQLiteDatabase`, `LocalDataStore`).

## Tests

`macgitTests/` uses XCTest. Integration tests (`*IntegrationTests`) create temporary git repositories and run real git commands, so they are the right place to cover `GitStatusService` and undo behavior.
