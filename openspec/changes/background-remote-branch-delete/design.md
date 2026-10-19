# Design

## Context

- `BranchSheetView.deleteSelectedBranches()` (`macgit/Views/Common/BranchSheetView.swift`) runs the whole batch inside `onRunRepositoryOperation("Deleting branches...")`. For each selected local branch it validates, reads the tip and upstream, runs `GitRemoteUndoSupport().remoteHash` (a network `git ls-remote`) when a matching remote target exists, deletes the local branch, deletes the remote branch, and registers the undo entry through its private `registerDeletedBranchUndo`. Selected remote branches are deleted with no undo entry. Failures are gathered into `deletionSummary` and shown in the sheet's alert, and the sheet stays open and reloads its data.
- The sheet has three hosts, all passing `onRunRepositoryOperation`:
  - `MainWindowView+Sheets.branchSheet`
  - `SidebarBranchPresentationModifier`, for merged-branch deletion with `validateLocalBranchDeletion`
  - `SidebarDeletePrefixSheet`
- `SidebarView+BranchActions.swift` has its own single-branch delete with a copy of `registerDeletedBranchUndo`.
- `GitStatusService.deleteRemoteBranch(remote:name:in:)` runs plain `runGit(["push", remote, "--delete", name])`. Fetch and push instead call `credentialInjection(for:in:credentialResolver:...)` and then `runRemoteGit`.
- The background lane, `runBackgroundRemoteOperation`, and `waitForBackgroundIdle` already exist from `background-git-activity`.

## Goals / Non-Goals

**Goals:**
- Network work for batch deletion runs in the background lane.
- Git work lives in `GitStatusService`, and the undo entry construction is shared instead of duplicated.

**Non-Goals:**
- The sidebar context-menu deletes, single local branch (`SidebarView+BranchActions`) and single remote branch (`SidebarBranchPresentationModifier` remote delete confirmation). They stay foreground in this change. They can reuse the new service methods later.
- Credential injection for remote undo/redo operations in `GitUndoExecutor` (`.pushBranch`, `.deleteRemoteBranch`). That is unchanged, existing behavior.
- Making the local phase itself background.

## Decisions

### 1. Git work moves to `GitStatusService+BranchDeletion.swift`

New extension with value types in the same file:

- `GitLocalBranchDeletionRequest` (branch names, `force`, current branch, `matchingRemoteTargets: [String: RemoteBranchDeleteTarget]`)
- `GitDeletedLocalBranch` (name, tip, upstream, force, remote target)
- `GitBranchDeletionFailure` (name, message), replacing `BranchSheetView.BranchDeletionFailure`, with `deletionSummary` moved alongside
- `GitPendingRemoteBranchDeletion` (target, optional `GitDeletedLocalBranch`)

Functions:

- `deleteLocalBranches(_ request:, validate: (@MainActor (String) async throws -> String)?, in:) async -> (deleted: [GitDeletedLocalBranch], failures: [GitBranchDeletionFailure])`. This is the current local half of the loop: current-branch guard, validated-tip check, `deleteValidatedMergedBranch`/`deleteBranch`, and the friendly error mapping (moved from the sheet). It runs no network commands.
- `deleteRemoteBranches(_ pending: [GitPendingRemoteBranchDeletion], in:, credentialResolver:) async -> [(GitPendingRemoteBranchDeletion, remoteHash: String?, error: GitBranchDeletionFailure?)]`. Each target runs in order, and the loop continues after a failure. For targets with a local branch, it first looks up the remote hash, then deletes.
- `deleteRemoteBranch(remote:name:in:credentialResolver: = nil, credentialInjector:, sshCredentialInjector:)` uses `credentialInjection` + `runRemoteGit`, mirroring `fetch(remote:)`. Existing callers keep compiling through the defaulted resolver, which gives the configured-helpers behavior they have today.
- `remoteBranchHash(remote:branch:in:credentialResolver:)` is a credentialed `ls-remote` for the undo hash. `GitRemoteUndoSupport.remoteHash` stays as is for the undo executor.

**Why:** the project rules put git execution in `GitStatusService*.swift`. The background phase outlives the sheet, so it cannot live in the view.

### 2. Shared undo entry builder in `GitBranchUndoSupport`

Add `static func deletedBranchUndoEntry(repositoryURL:branch:force:tip:upstream:remoteTarget:remoteHash:) -> GitUndoEntry`, with the same operations and label as today, except one ordering fix. Undo now pushes the remote branch back before `setUpstream`, because when the upstream is the deleted remote-tracking ref (`origin/<branch>`), `git branch --set-upstream-to` fails until the push recreates it. The previous order made undo of a local+remote delete fail. Both the sheet path and `SidebarView+BranchActions.registerDeletedBranchUndo` call it, which removes the duplicate.

### 3. Phase coordination

- **Sheet (local phase):** on confirm, `onRunRepositoryOperation("Deleting branches...")` calls `GitStatusService.shared.deleteLocalBranches`. On the main actor it registers undo immediately for deleted branches without a remote target. It then builds `GitPendingRemoteBranchDeletion`s (remote targets of deleted locals plus selected remote branches not already covered) and hands them to `onRunBackgroundRemoteBranchDeletion` if the list is non-empty. It calls `onCompleted()` when anything was deleted. With no local failures it calls `dismiss()`. Otherwise it reloads the delete data and shows `deletionSummary` for the local failures.
- **Host (remote phase):** `MainWindowView+BranchDeletion.swift` adds `runBackgroundRemoteBranchDeletion(_ pending:)`, which calls `runBackgroundRemoteOperation(title, remotes: unique remotes)`. Credentials, including any reconnect UI, are resolved before queueing. The operation calls `deleteRemoteBranches`, registers a `deletedBranchUndoEntry` on the main actor for each pending item with a local branch (with remote target and hash on success, without on failure), refreshes through `syncState.refresh`, posts `.repositoryDidChange` and `.repositoryRemoteRefsDidRefresh`, and returns `.succeeded` or `.failed(message)`.
- **Failure message:** first line `Could not delete X of N remote branches.`, then a blank line and `• <remote>/<branch>: <message>` per failure. `RepositoryOperationProgress.backgroundErrorSummary` then uses the count line as the summary.
- **Title:** `Deleting <remote>/<branch>` when N == 1, otherwise `Deleting N remote branches`.

**Window scoping:** the closure is created in `MainWindowView` and captures that window's `operationProgress`, `syncState`, `undoManager`, and credential resolver. It is passed down as a plain callback (`SidebarView` → `SidebarBranchPresentationModifier` / `SidebarDeletePrefixSheet` → `BranchSheetView`). There is no notification routing, so it cannot reach another window.

**Alternative:** queueing one background item per remote target. It was rejected because one confirmation should read as one activity, and the itemized detail already lists each branch.

### 4. Ordering change for the hash lookup

Today the remote hash is read before the local delete, so a failing `ls-remote` keeps the local branch. In the new flow the local branch is already deleted when the background phase reads the hash. A hash-lookup failure is therefore treated like a remote-delete failure: the remote is not deleted, the local-only undo entry is registered, and the failure is listed. The local branch can still be restored with Undo, so no data is lost.

## Risks / Trade-offs

- [The sidebar still lists remote branches until the background item finishes, and the user may act on one] → Remote refresh follows completion, and git reports a clear error if the ref is gone.
- [Undo for a branch with a remote target is unavailable until its remote phase finishes] → Undo already waits for the background lane (`executeUndoEntry` → `waitForBackgroundRemoteActivity`), so the entry is registered by the time undo runs.
- [A local delete of a packed branch can race with a pruning fetch on `packed-refs.lock`] → Git retries the packed-refs lock (`core.packedRefsTimeout`). Any failure is surfaced in the local alert. Rare, and acceptable.
- [Credential injection changes how remote deletes authenticate] → With no matching provider account, `credentialInjection` returns `.configuredGitHelpers()`, the same helpers path that plain `runGit` used.

## Migration Plan

Client-only change. No persisted data, synced settings, or Firebase contract changes.
