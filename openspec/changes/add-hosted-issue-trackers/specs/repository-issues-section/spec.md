# Spec Delta

## Purpose

Defines the ISSUES section of the repository sidebar, which groups issue-tracker integrations (Jira and the repository's hosted issue tracker) separately from the repository's own Workspace items.

## ADDED Requirements

### Requirement: Issue trackers have their own sidebar section
The repository sidebar SHALL show an ISSUES section directly below the Workspace section. Issue-tracker rows, including Jira, SHALL appear only in this section and SHALL NOT appear in the Workspace section.

#### Scenario: Section placement
- **WHEN** the user opens a repository window with Show Issues on
- **THEN** the ISSUES section appears between Workspace and Branches
- **AND** Workspace does not list Jira

### Requirement: One setting controls the ISSUES section
A single "Show Issues" setting SHALL hide or show the whole ISSUES section in every repository window. It SHALL be available in General settings under Repository Sidebar and in the sidebar background context menu. It SHALL default to on, and SHALL use the existing synced Jira visibility value so that earlier choices carry over. There SHALL be no per-row visibility toggles.

#### Scenario: Default
- **WHEN** the user has never changed Show Issues
- **THEN** the ISSUES section is shown

#### Scenario: Hide from settings
- **WHEN** the user turns off "Show Issues" in General settings
- **THEN** the ISSUES section disappears from every open repository window and stays hidden after relaunch

#### Scenario: Earlier Jira choice carries over
- **WHEN** a user who had hidden Jira in an earlier version updates
- **THEN** Show Issues is off

#### Scenario: Toggle from the sidebar
- **WHEN** the user chooses "Show Issues" in the sidebar background context menu
- **THEN** the section's visibility flips and General settings reflects the change

### Requirement: The ISSUES section collapses like other sections
Clicking the ISSUES header SHALL collapse or expand the section. The expanded state SHALL be remembered per repository and SHALL default to expanded.

#### Scenario: Collapse
- **WHEN** the user clicks the ISSUES header while it is expanded
- **THEN** its rows are hidden immediately and stay hidden when the repository is reopened

### Requirement: Rows in the ISSUES section
The section SHALL list Jira, followed by one hosted tracker row when the repository has a remote recognized as GitHub, GitLab, Bitbucket, or Azure Repos. The hosted row SHALL be titled "GitHub Issues", "GitLab Issues", "Bitbucket Issues", or "Azure Boards" and use that provider's icon. Without a recognized remote, the hosted row SHALL be absent.

#### Scenario: GitHub repository
- **WHEN** the repository's `origin` remote points to github.com
- **THEN** the section lists "Jira" and "GitHub Issues"

#### Scenario: Local-only repository
- **WHEN** the repository has no remote
- **THEN** the section lists only "Jira"

#### Scenario: Remote added later
- **WHEN** the user adds a GitLab remote to a repository that had none
- **THEN** a "GitLab Issues" row appears without reopening the window

### Requirement: The hosted row follows the preferred remote
When several remotes are recognized, the hosted row SHALL use the provider of the remote chosen for the issue screen: the remembered choice for this repository, otherwise `origin`, otherwise the first recognized remote.

#### Scenario: Remotes on different providers
- **WHEN** `origin` is a GitLab remote and `mirror` is a GitHub remote, and no choice is remembered
- **THEN** the hosted row is titled "GitLab Issues"

### Requirement: A disappearing row cannot stay selected
When the selected row in the ISSUES section disappears, the window SHALL select File status. This applies when Show Issues is turned off and when the hosted row is removed.

#### Scenario: Hide while viewing issues
- **WHEN** the user turns off Show Issues while the GitHub Issues screen is selected
- **THEN** the window selects File status

#### Scenario: Remote removed
- **WHEN** the only recognized remote is removed while its issue screen is selected
- **THEN** the hosted row disappears and the window selects File status
