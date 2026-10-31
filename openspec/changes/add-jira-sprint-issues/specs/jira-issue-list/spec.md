# Spec Delta

## Purpose

Defines the Pro-gated Jira item in the repository sidebar's ISSUES section and its issue list screen, which shows the connected user's own Jira issues as a filterable flat list and lets them start a branch from an issue.

## ADDED Requirements

### Requirement: Jira appears in the sidebar ISSUES section
The repository sidebar SHALL list a "Jira" item first in the ISSUES section. Its visibility follows the single "Show Issues" setting, and selection falls back to File status when it disappears. Both are defined by the `repository-issues-section` capability. Jira SHALL NOT appear in the Workspace section.

#### Scenario: Default visibility
- **WHEN** the user opens a repository window with Show Issues on
- **THEN** the ISSUES section lists "Jira" and the Workspace section does not

#### Scenario: Hidden with the section
- **WHEN** the user turns off Show Issues while the Jira screen is selected
- **THEN** the window selects File status

### Requirement: The Jira issues screen requires Commit+ Pro
Selecting Jira SHALL show the issue list only when the `jiraIssues` plan feature is allowed for the signed-in account; it is allowed for active Pro and denied for Free. Otherwise the screen SHALL show the existing feature-access view with the matching sign-in or upgrade action and SHALL NOT contact Jira. While access is being checked, the screen SHALL show a progress state.

#### Scenario: Pro user
- **WHEN** a signed-in user with active Pro selects Jira
- **THEN** the Jira issues screen is shown

#### Scenario: Free user
- **WHEN** a signed-in Free user selects Jira
- **THEN** the screen explains that Jira requires Commit+ Pro and offers Upgrade
- **AND** no Jira request is made

#### Scenario: Signed out
- **WHEN** no Commit+ account is signed in and the user selects Jira
- **THEN** the screen asks the user to sign in

#### Scenario: Pro ends while the screen is open
- **WHEN** the account's Pro access ends while the Jira screen is shown
- **THEN** the screen switches to the upgrade view

### Requirement: Feature policy fallback keeps Jira Pro-only
When the remote feature policy has no valid `jiraIssues` entry or cannot be loaded, Commit+ SHALL use its bundled rule, which allows Jira issues for Pro and denies it for Free. A remote entry that disables the feature SHALL hide the issue list for all plans.

#### Scenario: Remote policy predates Jira
- **WHEN** the published feature policy has no `jiraIssues` entry
- **THEN** Pro users can open the Jira issues screen and Free users see the upgrade view

#### Scenario: Remote kill switch
- **WHEN** the published feature policy sets `jiraIssues` to disabled
- **THEN** the Jira screen shows that the feature is unavailable for every plan

### Requirement: The screen guides users who have not connected Jira
When access is allowed but no Jira site is connected, the screen SHALL explain that a Jira Cloud connection is needed and offer "Connect Jira", which opens Settings → Integrations. When the connection needs reconnection, the screen SHALL say so and offer to reconnect.

#### Scenario: No connection
- **WHEN** a Pro user opens the Jira screen without a Jira connection
- **THEN** the screen offers "Connect Jira"

#### Scenario: Connection needs reconnection
- **WHEN** Jira rejects the saved token while loading issues
- **THEN** the screen shows that the Jira connection needs to be reconnected and offers to open Settings → Integrations

### Requirement: The issue list shows the user's own issues
The screen SHALL list only issues assigned to the connected Jira user, as a flat list without columns or swimlanes. By default it SHALL show issues in open sprints whose status category is not Done, most recently updated first. Each row SHALL show the issue type, key, summary, status, priority, and sprint name when present.

#### Scenario: Default list
- **WHEN** a Pro user with a Jira connection opens the Jira screen
- **THEN** the list shows their assigned, not-done issues in open sprints, most recently updated first

#### Scenario: Issue assigned to someone else
- **WHEN** an issue in the user's sprint is assigned to another person
- **THEN** it does not appear in the list

#### Scenario: Many issues
- **WHEN** more issues match than fit in one Jira response
- **THEN** the list loads further results as the user scrolls to the end

### Requirement: The issue list can be filtered
The screen SHALL provide filters for sprint (open sprints, one specific sprint, backlog without a sprint, or any), status category (To Do, In Progress, Done), project, and issue type, plus a text search on key and summary. Specific sprints and projects SHALL be offered from those the user's issues belong to. Changing a filter SHALL reload the list, and a "Reset Filters" action SHALL restore the default.

#### Scenario: Filter by sprint
- **WHEN** the user chooses a specific sprint
- **THEN** only their issues in that sprint are listed

#### Scenario: Backlog
- **WHEN** the user chooses the backlog
- **THEN** only their issues that are not in any sprint are listed

#### Scenario: Include done issues
- **WHEN** the user adds Done to the status filter
- **THEN** done issues that match the other filters are listed too

#### Scenario: Search by key
- **WHEN** the user types `PROJ-12` in search
- **THEN** the list shows matching issues by key or summary

#### Scenario: Reset filters
- **WHEN** the user chooses "Reset Filters"
- **THEN** the default filter is restored and the list reloads

### Requirement: Filters are remembered per repository
The selected filters SHALL be remembered for each repository on this Mac and restored when that repository's Jira screen is opened again, including after relaunch. Text search SHALL NOT be remembered.

#### Scenario: Return to a repository
- **WHEN** the user filters by project PROJ in repository A, then later reopens Jira in repository A
- **THEN** the PROJ project filter is still applied

#### Scenario: Different repository
- **WHEN** the user opens Jira in repository B
- **THEN** repository B uses its own remembered filters, or the default

### Requirement: Loading, empty, and error states are explicit
The screen SHALL show a loading state on first load, keep the current rows visible while refreshing, show an empty state that distinguishes "no matching issues" from "no issues at all", and show Jira errors with a Retry action. A "Refresh" action SHALL reload the list.

#### Scenario: No issues match the filter
- **WHEN** the filters match no issues
- **THEN** the screen says no issues match and offers "Reset Filters"

#### Scenario: Network failure
- **WHEN** Jira cannot be reached
- **THEN** the screen shows that Jira could not be reached and offers Retry
- **AND** previously loaded rows, if any, stay visible

#### Scenario: Rate limited
- **WHEN** Jira responds that requests are rate limited
- **THEN** the screen says Jira is busy and offers Retry

### Requirement: Issues can be opened and copied
Each issue SHALL offer "Open in Jira", which opens the issue in the default browser, "Copy Key", and "Copy Key and Summary". Double-clicking or pressing Return on a row SHALL open it in Jira.

#### Scenario: Open in Jira
- **WHEN** the user double-clicks an issue
- **THEN** the issue's page on the connected Jira site opens in the default browser

#### Scenario: Copy key and summary
- **WHEN** the user chooses "Copy Key and Summary" on PROJ-123 "Fix login crash"
- **THEN** the pasteboard contains `PROJ-123 Fix login crash`

### Requirement: Selecting an issue shows its details
Single-clicking an issue SHALL show a details panel on the right of the list with the issue's key, type, summary, status, priority, project, sprints, and last update. The panel SHALL offer the same actions as the issue's context menu: create a branch, "Open in Jira", "Copy Key", and "Copy Key and Summary". Closing the panel or clearing the selection SHALL hide it.

#### Scenario: Select an issue
- **WHEN** the user single-clicks PROJ-123 in the list
- **THEN** the details panel shows PROJ-123's summary, status, type, priority, project, sprints, and last update
- **AND** it offers the branch, open, and copy actions

#### Scenario: Close the panel
- **WHEN** the user chooses Close in the details panel
- **THEN** the panel hides and the list uses the full width

#### Scenario: Selected issue leaves the list
- **WHEN** a refresh or filter change removes the selected issue from the list
- **THEN** the details panel hides

### Requirement: A branch can be created from an issue
Each issue SHALL offer to create a branch with a prefilled, editable name built from the issue key and summary, through the existing branch or Git Flow start flow of the current repository. With Git Flow configured, the choices SHALL be Start Feature, Start Bugfix, Start Hotfix, and New Branch, and the suggested choice SHALL be Start Bugfix for Bug or Defect issues and Start Feature otherwise. Without Git Flow, only New Branch is offered. Commit+ SHALL NOT change the issue in Jira.

#### Scenario: Plain repository
- **WHEN** the user chooses "Create Branch…" on PROJ-123 "Fix login crash" in a repository without Git Flow
- **THEN** the branch sheet opens with the name `PROJ-123-fix-login-crash`
- **AND** creating it behaves like any other branch creation, including undo and repository refresh

#### Scenario: Bug in a Git Flow repository
- **WHEN** the user creates a branch from a Bug issue PROJ-123 "Fix login crash" using the suggested choice in a repository with Git Flow configured
- **THEN** the Git Flow bugfix start sheet opens with `PROJ-123-fix-login-crash` as the topic name

#### Scenario: Story in a Git Flow repository
- **WHEN** the user creates a branch from a Story issue using the suggested choice in a repository with Git Flow configured
- **THEN** the Git Flow feature start sheet opens with the suggested name

#### Scenario: Choose a different flow
- **WHEN** the user picks Start Hotfix or New Branch instead of the suggested choice
- **THEN** that flow's sheet opens with the suggested name

#### Scenario: Release is not offered
- **WHEN** the user opens the branch choices for an issue in a Git Flow repository
- **THEN** Start Release is not listed, because release names are versions rather than issues

#### Scenario: Summary with unsupported characters
- **WHEN** the issue summary contains punctuation, non-ASCII letters, or is very long
- **THEN** the suggested name keeps the issue key, uses only lowercase ASCII letters, digits, and single hyphens after it, and is at most 60 characters

#### Scenario: Branch already exists
- **WHEN** a branch with the suggested name already exists
- **THEN** the branch flow reports the conflict as it does for any existing name

#### Scenario: Jira unchanged
- **WHEN** a branch is created from an issue
- **THEN** no request that modifies the issue is sent to Jira
