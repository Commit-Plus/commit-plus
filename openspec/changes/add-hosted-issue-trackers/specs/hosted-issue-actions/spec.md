# Spec Delta

## Purpose

Defines the write actions on hosted issue trackers available from the hosted issue screen: creating an issue, commenting, and closing or reopening, each performed with the user's connected provider account.

## ADDED Requirements

### Requirement: Write actions follow the screen's access
Write actions SHALL be available only when the hosted issue screen is allowed for the repository. Every write SHALL use the same remote and provider account as the list. Each write SHALL start only from an explicit user action, and the app SHALL NOT send writes in the background or retry them automatically.

#### Scenario: Access denied
- **WHEN** `hostedIssues` is denied for the repository
- **THEN** no create, comment, close, or reopen action is offered

#### Scenario: Failed write is not retried
- **WHEN** posting a comment fails because of a network error
- **THEN** the error is shown, the draft text is kept, and nothing is sent until the user tries again

### Requirement: Create an issue
The screen SHALL offer "New Issue…", which opens a sheet with a required title and an optional Markdown description. For Azure Boards, the sheet SHALL also require a work item type chosen from the project's types. Creating SHALL be disabled while the title is blank or a request is in progress. On success, the new issue SHALL be selected in the list.

#### Scenario: Create on GitHub
- **WHEN** the user creates an issue titled "Crash on launch" in GitHub Issues
- **THEN** the issue is created on the repository and appears selected in the list

#### Scenario: Azure work item type
- **WHEN** the user opens "New Issue…" on Azure Boards
- **THEN** the sheet lists the project's work item types and requires one

#### Scenario: Blank title
- **WHEN** the title is empty or whitespace
- **THEN** Create is disabled

#### Scenario: Cancel keeps nothing
- **WHEN** the user cancels the sheet
- **THEN** no request is sent

### Requirement: Comment on an issue
The detail pane SHALL offer a comment field with a Comment action. Posting SHALL be disabled while the text is blank or a request is in progress. On success, the field SHALL clear and the new comment SHALL appear in the detail.

#### Scenario: Post a comment
- **WHEN** the user posts "Fixed in main" on issue #42
- **THEN** the comment appears at the end of the issue's comments

### Requirement: Close and reopen an issue
The detail pane SHALL offer Close for an open issue and Reopen for a closed one. On Azure Boards, Close SHALL move the work item to the first state of its type in the Completed category, and Reopen SHALL move it to the first state in the Proposed category. On Bitbucket, Close SHALL set the state to resolved and Reopen SHALL set it to open.

#### Scenario: Close and undo by reopening
- **WHEN** the user closes issue #42 and then chooses Reopen
- **THEN** the issue is open again on the tracker

#### Scenario: Azure type without a Completed state
- **WHEN** a work item's type has no state in the Completed category
- **THEN** Close is unavailable for that work item and the reason is shown

### Requirement: Results refresh after a write
After a successful write, the affected issue's detail and the list SHALL be reloaded from the tracker, keeping the user's selection and scroll position. A row that no longer matches the active filter SHALL stay visible until the next refresh, so it does not vanish while the user is looking at it.

#### Scenario: Close under the Open filter
- **WHEN** the user closes an issue while the list shows Open issues
- **THEN** the issue stays selected and shows Closed until the list is next refreshed

### Requirement: Write permission errors are explained
When the tracker rejects a write because the account lacks permission, the screen SHALL say which permission is missing, such as Bitbucket issue write scope, Azure DevOps Work Items (Read & write) scope, or repository access on GitHub or GitLab. The user's input SHALL be kept.

#### Scenario: Read-only Azure PAT
- **WHEN** the Azure PAT has Work Items (Read) but not (Read & write) and the user posts a comment
- **THEN** the screen says the token needs Work Items (Read & write) and the comment text is kept

### Requirement: Issue writes are not app undo actions
Issue writes SHALL NOT be added to the repository undo history, because they change the tracker and not the repository. Close and Reopen SHALL be the way to reverse each other.

#### Scenario: Undo after closing an issue
- **WHEN** the user closes an issue and then chooses Edit → Undo
- **THEN** the issue is not reopened, and the most recent repository action, if any, is undone instead
