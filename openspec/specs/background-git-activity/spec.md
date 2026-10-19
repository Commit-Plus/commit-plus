# background-git-activity Specification

## Purpose

Lets network-bound Git actions that do not touch the index, working tree, or HEAD run without blocking the repository window, and shows their progress and failures in a header activity indicator and popover.

## Requirements

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

### Requirement: Blocking actions keep the global overlay
Every Git action not listed as background-safe SHALL keep the existing full-window overlay and cancel behavior. This includes actions that write the index, working tree, or HEAD, and pull, update current branch, and fetch-and-fast-forward of a branch.

#### Scenario: Checkout still blocks
- **WHEN** the user checks out a branch
- **THEN** the full-window overlay appears exactly as before this change

#### Scenario: Pull still blocks
- **WHEN** the user confirms the Pull sheet
- **THEN** the full-window overlay appears for the duration of the pull

### Requirement: Local actions stay available during background actions
While background actions are running, local actions (commit, stage, unstage, stash, branch, tag, checkout, merge, rebase) SHALL stay enabled, as if no remote operation were running.

#### Scenario: Commit during a fetch
- **WHEN** a background fetch is running and the user opens the Commit sheet and commits
- **THEN** the commit succeeds and the fetch continues

### Requirement: Background actions run one at a time per repository
Within one repository window, background actions SHALL execute one at a time in the order requested. Later requests SHALL wait in a queued state. Different repository windows SHALL run independently.

#### Scenario: Second action waits
- **WHEN** a push is running and the user starts a fetch in the same window
- **THEN** the fetch appears as queued and starts after the push finishes

#### Scenario: Other windows are independent
- **WHEN** a fetch is running in repository window A
- **THEN** a fetch started in repository window B starts immediately

### Requirement: Remote-ref foreground actions wait for the background lane
Blocking actions that update remote-tracking refs (pull, update current branch, fetch-and-fast-forward, undo or redo of a remote entry) SHALL start only after the window's background lane has no running or queued actions. The overlay stays visible while they wait.

#### Scenario: Pull while a fetch is running
- **WHEN** a background fetch is running and the user confirms the Pull sheet
- **THEN** the overlay shows the pull message, and the pull starts only after the fetch finishes

### Requirement: Header indicator shows background state
The repository-name component in the window header SHALL show the provider icon when the lane is idle with no failures, a progress indicator while any action is running or queued, and a red error icon when a failed item remains and nothing is running.

#### Scenario: Running state
- **WHEN** a background fetch starts
- **THEN** the provider icon is replaced by a progress indicator

#### Scenario: Failure state
- **WHEN** the only background action fails
- **THEN** the progress indicator is replaced by a red error icon

#### Scenario: Return to idle
- **WHEN** the last background action succeeds and no failed items remain
- **THEN** the provider icon is shown again

### Requirement: Repository name opens the activity popover
Clicking the repository-name component SHALL open a popover listing the window's running, queued, and failed background actions, each with a title (for example `Fetching remotes`). The notification bell SHALL remain a separate control with its own behavior.

#### Scenario: Open popover
- **WHEN** the user clicks the repository name while a push is running
- **THEN** a popover lists the push with a running state

#### Scenario: Empty popover
- **WHEN** the user clicks the repository name with no background activity
- **THEN** the popover shows an empty state saying no background Git actions are running

#### Scenario: Bell is independent
- **WHEN** the user clicks the notification bell
- **THEN** the notification popover opens and the activity popover does not

### Requirement: Successful actions remove themselves
A background action that succeeds SHALL be removed from the popover without user action, and SHALL trigger the same repository refresh and notifications as before this change.

#### Scenario: Fetch success
- **WHEN** a background fetch succeeds
- **THEN** its item disappears from the popover and remote refs in the sidebar and history refresh

### Requirement: Failed actions show a short error and detail view
A failed background action SHALL stay in the popover with a one-line error summary, a View button, and a dismiss control. View SHALL open a modal with the full error text, which can be selected and copied. The blocking Error alert SHALL NOT be shown for background failures.

#### Scenario: Push rejected
- **WHEN** a background push is rejected by the remote
- **THEN** no Error alert appears, the header shows the error icon, and the popover item shows a short error message with a View button

#### Scenario: View detail
- **WHEN** the user clicks View on a failed item
- **THEN** a modal shows the complete error message with a control to copy it

#### Scenario: Dismiss failure
- **WHEN** the user dismisses the last failed item and nothing is running
- **THEN** the item is removed and the header returns to the provider icon

### Requirement: Partial fetch success is reported and applied
When a background fetch updates some remotes and fails on others, the successful remote updates SHALL be refreshed into the UI and the item SHALL be reported as failed with the failing remotes' error.

#### Scenario: One remote fails
- **WHEN** a fetch of all remotes succeeds for `origin` and fails for `upstream`
- **THEN** `origin` refs refresh and the popover shows a failed item describing the `upstream` error

### Requirement: Background activity is scoped to its window
Background items, header state, and the popover SHALL belong to the repository window that started the action. Closing the window SHALL cancel its running background action and discard its items.

#### Scenario: Two windows
- **WHEN** a push fails in repository window A
- **THEN** only window A shows the error icon and failed item

### Requirement: Undo registration after background success
A background push that publishes a new branch SHALL register its undo entry only after the push succeeds, as before this change.

#### Scenario: Publish then undo
- **WHEN** a background push publishes a new branch and succeeds
- **THEN** the Undo menu offers undoing the publish

### Requirement: Background status reads avoid optional locks
Repository status reads triggered by background-action refreshes SHALL NOT take the index lock, so concurrent user staging or committing does not fail with an index.lock error.

#### Scenario: Stage during fetch refresh
- **WHEN** a background fetch finishes and refreshes status while the user stages a file
- **THEN** staging does not fail with "Unable to create index.lock"

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
