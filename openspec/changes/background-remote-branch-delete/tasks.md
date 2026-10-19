# Tasks

## 1. Git service for branch deletion

- [x] 1.1 Add credential injection to `GitStatusService.deleteRemoteBranch` (resolver defaulted to nil, `credentialInjection` + `runRemoteGit`, as in `fetch(remote:)`) and add `remoteBranchHash(remote:branch:in:credentialResolver:)`. Verify in a new `GitBranchDeletionIntegrationTests` (temporary repo + bare remote): deleting `origin/x` removes it from the bare remote, and a resolver that throws (for example with two matching accounts, as in `GitProviderCredentialResolverTests.testMultipleMatchingAccountsThrows`) for an `https://github.com/...` remote makes `deleteRemoteBranch` throw before any network call.
- [x] 1.2 Add `GitStatusService+BranchDeletion.swift` with the value types, moved `deletionSummary`/friendly error mapping, and `deleteLocalBranches(_:validate:in:)`. Verify in `GitBranchDeletionIntegrationTests`: merged and forced deletes succeed with the tip and upstream captured, the current branch and a not-fully-merged branch (force off) are reported as failures while the others are deleted, a validated tip mismatch is a failure, and no `ls-remote`/`push` runs (the bare remote is untouched).
- [x] 1.3 Add `deleteRemoteBranches(_:in:credentialResolver:)`. Verify in `GitBranchDeletionIntegrationTests`: three targets with one already missing on the server delete the other two, capture hashes for targets that have local branches, report the missing one with the friendly "does not exist" message, and continue after the failure.
- [x] 1.4 Move `BranchSheetView.deletionSummary` tests to the new types and add a test for the remote failure message format (`Could not delete X of N remote branches.` first line plus bullets). Verify by running `BranchSheetInitialStateTests` and `GitBranchDeletionIntegrationTests`.

## 2. Shared undo entry

- [x] 2.1 Add `GitBranchUndoSupport.deletedBranchUndoEntry(...)` and switch `SidebarView+BranchActions.registerDeletedBranchUndo` to it. Same operations, except undo now pushes the remote back before `setUpstream`: the old order failed whenever the upstream was the deleted remote-tracking ref, which the new test exposed. Verify in `GitUndoBranchIntegrationTests`: an entry with a remote target, executed via `GitUndoExecutor`, recreates the local branch with upstream and pushes the remote back at the old hash, and redo deletes both. An entry without a remote target only touches the local branch.

## 3. Sheet and host coordination

- [x] 3.1 Add `MainWindowView+BranchDeletion.swift` with `runBackgroundRemoteBranchDeletion(_:)` (title rule, unique remotes for credential resolution, undo registration per pending item, refresh + `.repositoryDidChange`/`.repositoryRemoteRefsDidRefresh`, outcome message). Verify that the app target compiles.
- [x] 3.2 Replace `BranchSheetView.deleteSelectedBranches` with the local phase: service call, immediate undo for branches without remote targets, building pending remote work, calling the new required `onRunBackgroundRemoteBranchDeletion`, then dismissing on full local success or showing the local-only failure alert and reloading. Remove the sheet's private `registerDeletedBranchUndo`. Verify by grep that `BranchSheetView.swift` no longer calls `deleteRemoteBranch` or `GitRemoteUndoSupport`, and that the app target compiles.
- [x] 3.3 Pass `runBackgroundRemoteBranchDeletion` through `MainWindowView+Sheets.branchSheet`, `SidebarView`, `SidebarBranchPresentationModifier` (merged), and `SidebarDeletePrefixSheet`, and update the `#Preview`. Verify with `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.

## 4. Integration validation

- [x] 4.1 (2026-10-19: verified by user in the running app) Manual UI review in the running app with a temporary repo and a slowed local bare remote (`remote.origin.receivepack "sleep 4; git-receive-pack"`):
  - Deleting three branches with matching remotes closes the sheet right after the brief overlay, and one `Deleting 3 remote branches` item runs in the header.
  - Pre-deleting one remote branch on the server yields a red item whose detail lists it.
  - Undo restores the local and remote branches.
  - A not-fully-merged branch with force off keeps the sheet open with a local-only alert.
  - The merged-branches and prefix delete entry points behave the same.
- [x] 4.2 Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitBranchDeletionIntegrationTests -only-testing:macgitTests/GitUndoBranchIntegrationTests -only-testing:macgitTests/BranchSheetInitialStateTests -only-testing:macgitTests/GitProviderCredentialResolverTests -only-testing:macgitTests/RepositoryOperationProgressTests test` and report the results.
- [x] 4.3 Run `git diff --check` and verify that there are no whitespace errors.
