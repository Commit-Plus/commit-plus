# Spec Delta

## MODIFIED Requirements

### Requirement: Remote branch operations use provider credentials
Remote branch deletion, the remote hash lookup used for undo, and undo or redo operations that push or delete a remote branch SHALL use the window's connected GitHub or GitLab credentials for the remote, the same way push and fetch do. When no provider account applies, they SHALL use git's configured credential helpers. If the user cancels a required account choice, the undo or redo entry SHALL be restored.

#### Scenario: Token-only HTTPS remote
- **WHEN** the remote is HTTPS and authenticates only through a connected Commit+ GitHub account
- **THEN** deleting the remote branch succeeds without a system credential prompt

#### Scenario: Undo restores remote with app token
- **WHEN** the user undoes "Delete branch topic" whose remote `origin/topic` was deleted, on a token-only HTTPS remote
- **THEN** the remote branch is pushed back using the connected account's token

## ADDED Requirements

### Requirement: Sidebar deletes use the same phases
The sidebar Delete branch command SHALL delete the local branch under the overlay and, when "Also delete remote branch" is on, queue its remote target as a background item with the same undo rules as the Delete Branches sheet. The sidebar Delete remote branch command SHALL queue the remote branch as a background item without a local phase. On success, a selection of that remote branch SHALL fall back to History.

#### Scenario: Local with remote from sidebar
- **WHEN** the user deletes `topic` from the sidebar with "Also delete remote branch" on
- **THEN** `topic` is deleted under a brief overlay, `Deleting origin/topic` runs in the background, and Undo afterwards restores both

#### Scenario: Remote only from sidebar while selected
- **WHEN** `origin/topic` is selected and the user deletes it from the sidebar
- **THEN** after the background item succeeds the selection moves to History
