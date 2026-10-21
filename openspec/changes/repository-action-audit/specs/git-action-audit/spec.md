# Spec Delta

## Purpose

Records the mutating Git commands the app runs for each repository during the current app session, with their origin and result, and lets the user review them from the repository window's activity popover.

## ADDED Requirements

### Requirement: Mutating Git commands are recorded
Every Git command the app runs that can change a repository or its remote-tracking state SHALL be recorded when it finishes, whether it succeeds, fails, or is cancelled. Read-only queries SHALL NOT be recorded.

#### Scenario: Fetch is recorded
- **WHEN** the app runs `git fetch --prune origin` for a repository and it succeeds
- **THEN** an audit record for that repository is added with the command, a success status, and the time it finished

#### Scenario: Failed push is recorded
- **WHEN** a push to `origin` is rejected by the remote
- **THEN** an audit record is added with a failure status and Git's error output

#### Scenario: Read-only query is not recorded
- **WHEN** the app runs `git status` or `git log` to refresh the window
- **THEN** no audit record is added

#### Scenario: Staging a hunk is recorded
- **WHEN** the user stages selected lines of a file
- **THEN** an audit record for the `git apply --cached` command is added

### Requirement: Audit records carry their origin
Each audit record SHALL be marked as User when it results from a user action, including actions the user confirmed for Repository AI, and as System when the app started it on its own, such as an automatic fetch.

#### Scenario: Automatic fetch is System
- **WHEN** the app fetches remotes automatically on its interval or on activation
- **THEN** the resulting records are marked System

#### Scenario: Fetch sheet is User
- **WHEN** the user confirms the Fetch sheet
- **THEN** the resulting records are marked User

### Requirement: Recorded commands and output exclude credentials
The recorded command SHALL redact credential-bearing arguments (tokens, passwords, authorization headers, and user information in URLs), and the recorded output SHALL redact user information embedded in URLs. Environment variables and injected credentials SHALL NOT be recorded.

#### Scenario: URL with credentials
- **WHEN** a recorded command's argument is `https://user:secret@example.com/repo.git`
- **THEN** the recorded command shows the URL without the password and with the user replaced by a redaction marker

### Requirement: Recorded output is bounded
The recorded output of a single command SHALL be limited to a fixed size, and the record SHALL indicate when output was truncated. Each repository SHALL keep at most a fixed number of most recent records in a session, discarding the oldest.

#### Scenario: Large output
- **WHEN** a recorded command produces more output than the limit
- **THEN** the stored output is cut at the limit and the detail pane states that the output was truncated

#### Scenario: Row cap
- **WHEN** a repository exceeds the record cap during a session
- **THEN** its oldest records are removed and the newest are kept

### Requirement: Audit is stored on disk, not in memory
Audit records SHALL be persisted to local disk storage as they are recorded. The app SHALL NOT keep the session's audit history in memory; the Audit tab SHALL load only item summaries for its list and SHALL read a command's output when that item is selected.

#### Scenario: Long session
- **WHEN** the app runs automatic fetches for several hours
- **THEN** audit records accumulate in on-disk storage and the app does not retain them in memory while the popover is closed

### Requirement: Audit covers only the current app session
The audit SHALL be cleared when the app terminates and again when the app launches, so it never shows records from a previous run, including a run that ended unexpectedly.

#### Scenario: Relaunch
- **WHEN** the user quits and reopens the app and opens the Audit tab
- **THEN** the list contains only actions from the new run

#### Scenario: After a crash
- **WHEN** the previous run ended without a normal termination
- **THEN** its records are not shown after the next launch

### Requirement: Audit is scoped to the repository
The Audit tab of a repository window SHALL list only records of commands run in that window's repository, including commands not started from that window, such as a command run from the Welcome window for the same repository.

#### Scenario: Two repositories
- **WHEN** repository windows A and B are open and the app fetches in A
- **THEN** the fetch appears in A's Audit tab and not in B's

### Requirement: Audit list shows action summaries
The Audit tab's list SHALL show records newest first. Each item SHALL show a short title derived from the command (for example `Fetch origin`), a one-line result summary, the time, a failure marker for failed or cancelled records, and a small User or System origin pill.

#### Scenario: Up-to-date fetch
- **WHEN** an automatic `git fetch` of `origin` produced no output
- **THEN** the item reads `Fetch origin` with the summary `Already up to date`, its time, and a System pill

#### Scenario: Failed item
- **WHEN** a recorded push failed
- **THEN** the item shows a failure marker and the first line of the error as its summary

### Requirement: Audit detail shows command and result
Selecting an audit item SHALL show, in the right pane, its title, status, date and time, the redacted command prefixed with `$ git`, and its recorded output. The command and output SHALL be selectable.

#### Scenario: Select an item
- **WHEN** the user selects `Fetch origin`
- **THEN** the right pane shows `$ git fetch --prune origin` and the output Git returned

#### Scenario: Command without output
- **WHEN** the user selects a successful command for which Git printed nothing
- **THEN** the right pane shows the command followed by a result line such as `Already up to date` for a fetch or `Completed with no output` otherwise

#### Scenario: Empty audit
- **WHEN** no mutating command has run for the repository in this session
- **THEN** the Audit tab shows an empty state saying no Git actions have been recorded yet

### Requirement: Audit updates while visible
While the Audit tab is open, newly recorded commands for its repository SHALL appear in the list without reopening the popover, and the current selection SHALL be kept.

#### Scenario: Fetch completes while open
- **WHEN** the Audit tab is open and an automatic fetch finishes
- **THEN** the new item appears at the top and the previously selected item stays selected
