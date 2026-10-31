# Spec Delta

## Purpose

Defines the hosted issue screen opened from the ISSUES section, which lists and shows issues from the repository's GitHub, GitLab, Bitbucket, or Azure Boards tracker using the user's connected provider account.

## ADDED Requirements

### Requirement: Supported trackers
The screen SHALL support GitHub.com and GitHub Enterprise Server issues, GitLab.com and self-managed GitLab issues, Bitbucket Cloud repository issues, and Azure DevOps Services work items. For Azure Repos remotes, the screen SHALL show work items of the remote's project rather than of the repository.

#### Scenario: Azure project scope
- **WHEN** the user opens Azure Boards for a remote in project `ChatApp`
- **THEN** the list shows work items of project `ChatApp`, including ones not linked to this repository

### Requirement: Hosted issues are gated like pull requests
Opening the screen SHALL require plan feature `hostedIssues`. Its bundled rule SHALL allow Free for public repositories and Pro for all repositories. When the remote policy lacks a valid entry or cannot load, the bundled rule SHALL apply. When access is denied, the screen SHALL show the feature-access view and SHALL NOT contact the provider.

#### Scenario: Free user, public repository
- **WHEN** a Free user opens GitHub Issues for a public GitHub repository
- **THEN** the issue list is shown

#### Scenario: Free user, private repository
- **WHEN** a Free user opens issues for a private repository
- **THEN** the screen offers Upgrade and makes no issue request

#### Scenario: Policy predates the feature
- **WHEN** the published feature policy has no `hostedIssues` entry
- **THEN** access follows the bundled rule

#### Scenario: Remote kill switch
- **WHEN** the published feature policy disables `hostedIssues`
- **THEN** the screen shows that the feature is unavailable for every plan

### Requirement: Issues load with the matching provider account
The screen SHALL use the connected provider account that the app already uses for this remote's pull requests and Git operations. When no matching account is connected or it needs reconnection, the screen SHALL say so and offer to open Settings → Connections. Credentials SHALL NOT appear in logs or error messages.

#### Scenario: No account
- **WHEN** the user opens GitLab Issues and no GitLab account matches the remote's host
- **THEN** the screen offers "Connect GitLab" and makes no issue request

#### Scenario: Expired token
- **WHEN** the provider rejects the saved token
- **THEN** the screen says the account needs to be reconnected and offers to open Settings → Connections

### Requirement: Bitbucket issues need the Atlassian account email
Bitbucket's REST API authenticates an API token with the Atlassian account email, not the Bitbucket username used for Git. The Bitbucket connection sheet SHALL offer an "Atlassian email" field, stored with the API token on this Mac only and never synced. When a Bitbucket account has no saved email, the issue screen SHALL say so and offer to open Settings → Connections; Git operations SHALL keep working without it.

#### Scenario: Account without email
- **WHEN** the user opens Bitbucket Issues with an account connected before the email field existed
- **THEN** the screen asks to add the Atlassian email to the Bitbucket account and makes no issue request

#### Scenario: Email is local
- **WHEN** the user saves an Atlassian email on one Mac and signs in on another Mac
- **THEN** the other Mac does not receive the email

### Requirement: Missing scope or disabled tracker is explained
When the provider reports that the tracker is turned off for the repository, the screen SHALL say so instead of showing an empty list. When the credential lacks the needed permission, the screen SHALL name the missing permission: Bitbucket issue scopes, Azure DevOps Work Items scope, or organization access for GitHub.

#### Scenario: GitHub issues disabled
- **WHEN** issues are turned off for the GitHub repository
- **THEN** the screen says issues are turned off for this repository and offers to open the repository in the browser

#### Scenario: Bitbucket token without issue scope
- **WHEN** the Bitbucket API token lacks issue read access
- **THEN** the screen says the token needs issue scopes and offers to open Settings → Connections

#### Scenario: Azure PAT without Work Items scope
- **WHEN** the Azure DevOps PAT cannot read work items
- **THEN** the screen says the token needs the Work Items scope

#### Scenario: GitHub organization restricts the app
- **WHEN** a GitHub organization blocks Commit+'s access to the repository
- **THEN** the screen explains that organization access must be granted and offers the existing organization access action

### Requirement: Remote choice for repositories with several trackers
When more than one remote has a supported tracker, the screen SHALL offer a remote picker that shows each remote's name and provider. The choice SHALL be remembered per repository on this Mac. The default SHALL be `origin`, otherwise the first recognized remote.

#### Scenario: Fork with upstream
- **WHEN** a repository has `origin` (the user's fork) and `upstream`, both on GitHub
- **THEN** the screen shows `origin` issues and offers a picker to switch to `upstream`

#### Scenario: Remembered choice
- **WHEN** the user picks `upstream` and later reopens the repository
- **THEN** the screen shows `upstream` issues

### Requirement: Default list and ordering
By default the list SHALL show open issues of the tracker, most recently updated first. Each row SHALL show the number or key, title, author, state, update time, and labels or tags when present. GitHub pull requests SHALL NOT appear as issues.

#### Scenario: Default list
- **WHEN** the user opens the screen for the first time
- **THEN** open issues are listed, most recently updated first

#### Scenario: GitHub pull requests are excluded
- **WHEN** a GitHub repository has open pull requests and open issues
- **THEN** only the issues are listed

#### Scenario: Many issues
- **WHEN** more issues match than one provider response contains
- **THEN** further results load as the user scrolls to the end

### Requirement: Filters
The screen SHALL filter by state (Open, Closed, All), relationship (All, Assigned to me, Created by me), and text search on title, number, or key. The state and relationship filters SHALL be remembered per repository and remote. Search text SHALL NOT be stored.

#### Scenario: Assigned to me
- **WHEN** the user chooses "Assigned to me"
- **THEN** only issues assigned to the connected account are listed

#### Scenario: Azure closed state
- **WHEN** the user chooses Closed on Azure Boards
- **THEN** work items whose state belongs to the Completed or Removed category are listed

#### Scenario: Search
- **WHEN** the user types `login` into search
- **THEN** the list shows matching issues from the tracker, not only already loaded rows

#### Scenario: Filtered empty result
- **WHEN** no issue matches the filters
- **THEN** the screen says no issues match and offers to clear the filters

### Requirement: Issue detail
Selecting an issue SHALL show its title, number or key, state, author, assignees, labels or tags, created and updated times, description, and comments in chronological order. Markdown SHALL render for GitHub, GitLab, and Bitbucket. Azure HTML descriptions and comments SHALL show as readable text without running scripts or loading remote content automatically.

#### Scenario: Open detail
- **WHEN** the user selects issue #42
- **THEN** the detail pane shows its description and comments

#### Scenario: Azure description
- **WHEN** an Azure work item description contains HTML formatting and an image
- **THEN** the text is readable and the image is not loaded automatically

### Requirement: Read-only issue actions
For any issue, the screen SHALL offer: open in browser, copy number or key, and copy reference with title. The number format SHALL be `#42` for GitHub, GitLab, and Bitbucket, and `AB#42` for Azure Boards.

#### Scenario: Copy reference
- **WHEN** the user copies the reference of GitHub issue 42 titled "Fix login"
- **THEN** the clipboard contains `#42 Fix login`

### Requirement: Create a branch from an issue
The screen SHALL offer to create a branch from an issue. The branch name SHALL be prefilled as `<number>-<slug of title>`, limited to 60 characters at a word boundary, and SHALL always keep the number. When Git Flow is configured, Git Flow start actions SHALL be offered with the same name. Nothing SHALL be written to the tracker.

#### Scenario: Plain branch
- **WHEN** the user creates a branch from issue 42 titled "Fix login on Safari"
- **THEN** the new branch sheet opens with `42-fix-login-on-safari`

#### Scenario: Git Flow feature
- **WHEN** Git Flow is configured and the user starts a feature from that issue
- **THEN** the Git Flow start sheet opens with topic `42-fix-login-on-safari`

### Requirement: Loading, errors, and refresh
The screen SHALL show progress while loading, keep the current rows while refreshing, and offer Retry after a failure. A rate-limit response SHALL say the provider is busy and when to retry if known. The screen SHALL refresh when it becomes visible again after more than one minute, and on demand.

#### Scenario: Rate limited
- **WHEN** GitHub returns a rate-limit response
- **THEN** the screen says GitHub is busy and offers Retry

#### Scenario: Refresh keeps rows
- **WHEN** the user refreshes a loaded list
- **THEN** existing rows stay visible until new results arrive
