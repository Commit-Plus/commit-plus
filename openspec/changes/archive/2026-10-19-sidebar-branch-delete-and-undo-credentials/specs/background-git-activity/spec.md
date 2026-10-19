# Spec Delta

## MODIFIED Requirements

### Requirement: Background-safe actions do not block the window
User-initiated fetch from the Fetch sheet, push from the Push sheet, push tag, force-push tag (after its existing confirmation), the remote phase of branch deletion from the Delete Branches sheet, and the remote phase of the sidebar Delete branch and Delete remote branch commands SHALL run in the repository window's background lane without showing the full-window operation overlay.

#### Scenario: Fetch runs without overlay
- **WHEN** the user confirms the Fetch sheet
- **THEN** no dimmed operation overlay appears and the user can keep selecting commits, staging files, and opening sheets while the fetch runs

#### Scenario: Push tag runs without overlay
- **WHEN** the user pushes a tag to a remote from the sidebar
- **THEN** the push runs in the background lane and the window stays interactive

#### Scenario: Remote branch deletion runs without overlay
- **WHEN** the user deletes branches with "Also delete matching remote branches" enabled
- **THEN** the overlay is shown only while the local branches are deleted, and the remote deletions run in the background lane while the window stays interactive

#### Scenario: Sidebar remote branch delete runs without overlay
- **WHEN** the user confirms Delete remote branch on `origin/topic` in the sidebar
- **THEN** no overlay appears and a `Deleting origin/topic` item runs in the background lane

## ADDED Requirements

### Requirement: Remote-only undo and redo run in the background
Undo or redo of an entry that contacts a remote and otherwise only changes branch, tag, or upstream refs (never the index, working tree, or HEAD) SHALL run as a background item titled `Undoing <label>` or `Redoing <label>`. On success the entry moves to the opposite stack with no alert. On failure the entry is restored and the item shows the error. All other undo and redo SHALL keep the blocking overlay.

#### Scenario: Undo remote branch publish
- **WHEN** the user undoes "Publish origin/topic"
- **THEN** after the existing confirmation, `Undoing Publish origin/topic` runs in the background and the window stays interactive

#### Scenario: Undo delete branch with remote
- **WHEN** the user undoes "Delete branch topic" whose remote was also deleted
- **THEN** the local branch, remote branch, and upstream are restored by a background item

#### Scenario: Local undo still blocks
- **WHEN** the user undoes a commit or a pull
- **THEN** the undo runs under the blocking overlay as before

#### Scenario: Background undo fails
- **WHEN** a background undo fails because the remote branch moved
- **THEN** the entry is back on the undo stack and the failed item shows the error message
