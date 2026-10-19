# Tasks

## 1. Undo credentials

- [x] 1.1 Add `GitStatusService.pushRefSpec(remote:refSpec:in:credentialResolver:)` and `GitUndoExecutor.execute(_:in:credentialResolver:)` with `remoteNames(in:)`. Verify in `GitUndoRemoteIntegrationTests`: `remoteNames` finds remotes inside sequences; with a throwing resolver (two matching accounts) on an `https://github.com/...` remote, `.pushBranch` and `.deleteRemoteBranch` throw the resolver error before running git; with a resolver and a local bare remote, the existing publish undo/redo round trip still succeeds.
- [x] 1.2 Make `executeUndoEntry` resolve credentials for operations with remotes and restore the entry on cancel. Verify that the app target compiles and that `GitUndoRemoteIntegrationTests` passes.

## 2. Sidebar deletes

- [x] 2.1 Route sidebar Delete branch through `deleteLocalBranches` plus the background remote phase, and remove the old inline delete and undo helper. Verify by grep that `SidebarView+BranchActions.swift` no longer calls `deleteRemoteBranch` or `GitRemoteUndoSupport`, and that the app target compiles.
- [x] 2.2 Route sidebar Delete remote branch to the background lane, and add the selection fallback in `runBackgroundRemoteBranchDeletion`. Verify with `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.

## 3. Background undo/redo

- [x] 3.1 Add `GitUndoExecutor.canRunInBackground(_:)`, extend `remoteNames` to `.replaceRemoteBranch`, and pass the resolver into the executor's `.replaceRemoteBranch` case. Verify in `GitUndoRemoteIntegrationTests`: delete-branch undo/redo entries, publish undo/redo, and force-push replace are eligible; pull undo (`resetHead`), commit undo, `createLocalBranch(checkout: true)`, and `updateLocalBranch` are not.
- [x] 3.2 Route eligible entries through `operationProgress.runInBackground` in `executeUndoEntry` (no info alert, restore on failure, `.failed` message), remove the top-level replace special case, and make `runUndoEntry` plus the confirmation dialog skip the overlay for eligible entries. Verify with `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`, then do a manual check: undo of a sidebar delete with remote shows `Undoing Delete branch …` in the header with no overlay, and undo of a commit still shows the overlay.

## 4. Validation

- [x] 4.1 (2026-10-19: verified by user in the running app) Manual UI review: sidebar Delete branch with the remote option and sidebar Delete remote branch run as background items, Undo restores both, and a selected deleted remote branch falls back to History.
- [x] 4.2 Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitUndoRemoteIntegrationTests -only-testing:macgitTests/GitBranchDeletionIntegrationTests -only-testing:macgitTests/GitUndoBranchIntegrationTests test` and run `git diff --check`.
