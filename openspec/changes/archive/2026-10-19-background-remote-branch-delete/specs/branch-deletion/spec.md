# Spec Delta

## Purpose

Defines how the Delete Branches sheet deletes local and remote branches: local work runs immediately, remote work runs in the background, and failures, undo, and provider credentials are handled consistently.

## ADDED Requirements

### Requirement: Local deletions complete before the sheet closes
Confirming Delete Branches SHALL first delete the selected local branches under the blocking overlay, applying the existing current-branch, merge-status, and force-delete rules. Remote deletions SHALL NOT run in this phase.

#### Scenario: Local and remote selected
- **WHEN** the user deletes local branches `a` and `b` with "Also delete matching remote branches" enabled
- **THEN** `a` and `b` are removed locally before the overlay closes, and `origin/a` and `origin/b` have not yet been deleted at that moment

#### Scenario: Current branch is rejected
- **WHEN** the selection includes the checked-out branch
- **THEN** that branch is not deleted and is reported as a local failure

### Requirement: Sheet closes or reports local failures
When every local deletion succeeds, the Delete Branches sheet SHALL close. When any local deletion fails, the sheet SHALL stay open and show an alert listing only the local failures, and SHALL refresh its branch list.

#### Scenario: All local deletions succeed
- **WHEN** all selected local branches are deleted
- **THEN** the sheet closes without an alert

#### Scenario: One local deletion fails
- **WHEN** one of three selected local branches is not fully merged and force delete is off
- **THEN** the sheet stays open with an alert naming that branch, and the other two are deleted

### Requirement: Remote deletions run as one background item
All remote targets of one confirmation SHALL be queued as a single background item. Targets are the matching remotes of locally deleted branches plus directly selected remote branches. The item is titled `Deleting <remote>/<branch>` for one target or `Deleting N remote branches` for several. Remote targets of local branches that failed to delete SHALL NOT be queued.

#### Scenario: Several targets
- **WHEN** three local branches with matching remotes are deleted
- **THEN** one background item titled `Deleting 3 remote branches` appears in the activity popover

#### Scenario: Local failure skips its remote
- **WHEN** local branch `a` fails to delete and `b` succeeds, both with matching remotes
- **THEN** only `origin/b` is queued for remote deletion

#### Scenario: No remote targets
- **WHEN** only local branches are deleted without the remote option
- **THEN** no background item is created

### Requirement: Remote deletion failures are itemized
Each remote target SHALL be attempted even if an earlier target fails. If any target fails, the background item SHALL fail with a summary that counts the failures (for example `Could not delete 1 of 3 remote branches.`) and a detail that lists each failed `<remote>/<branch>` with its error message. If every target succeeds, the item SHALL be removed.

#### Scenario: Partial remote failure
- **WHEN** `origin/b` was already deleted on the server and `origin/a`, `origin/c` delete successfully
- **THEN** `origin/a` and `origin/c` are gone, and the failed item's detail says `origin/b` does not exist or was already deleted

### Requirement: Undo registration follows remote completion
A local branch with no remote target SHALL get its undo entry right after the local phase. A local branch with a remote target SHALL get its undo entry when its remote deletion finishes. The entry restores local and remote if the remote delete succeeded, or only the local branch if it failed. Directly selected remote branches SHALL get no undo entry.

#### Scenario: Undo local and remote
- **WHEN** branch `a` and `origin/a` are deleted and the user chooses Undo
- **THEN** `a` is recreated at its old tip with its upstream, and `origin/a` is pushed back at its old hash

#### Scenario: Remote delete failed
- **WHEN** `a` is deleted locally but deleting `origin/a` fails
- **THEN** the undo entry for `a` only recreates the local branch

### Requirement: Remote branch operations use provider credentials
Remote branch deletion and the remote hash lookup used for undo SHALL use the window's connected GitHub or GitLab credentials for the remote, the same way push and fetch do. When no provider account applies, they SHALL use git's configured credential helpers.

#### Scenario: Token-only HTTPS remote
- **WHEN** the remote is HTTPS and authenticates only through a connected Commit+ GitHub account
- **THEN** deleting the remote branch succeeds without a system credential prompt

### Requirement: Remote phase refreshes repository state
After the remote phase finishes, with or without failures, the window SHALL refresh repository state and remote branch lists through the existing refresh and notification flow.

#### Scenario: Sidebar updates
- **WHEN** a background remote deletion of `origin/a` succeeds
- **THEN** `origin/a` disappears from the sidebar's remote branches without a manual refresh
