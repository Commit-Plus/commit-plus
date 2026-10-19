# Spec Delta

## MODIFIED Requirements

### Requirement: Background-safe actions do not block the window
User-initiated fetch from the Fetch sheet, push from the Push sheet, push tag, force-push tag (after its existing confirmation), and the remote phase of branch deletion from the Delete Branches sheet SHALL run in the repository window's background lane without showing the full-window operation overlay.

#### Scenario: Fetch runs without overlay
- **WHEN** the user confirms the Fetch sheet
- **THEN** no dimmed operation overlay appears and the user can keep selecting commits, staging files, and opening sheets while the fetch runs

#### Scenario: Push tag runs without overlay
- **WHEN** the user pushes a tag to a remote from the sidebar
- **THEN** the push runs in the background lane and the window stays interactive

#### Scenario: Remote branch deletion runs without overlay
- **WHEN** the user deletes branches with "Also delete matching remote branches" enabled
- **THEN** the overlay is shown only while the local branches are deleted, and the remote deletions run in the background lane while the window stays interactive
