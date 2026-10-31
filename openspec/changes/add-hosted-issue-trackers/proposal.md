# Proposal

## Why

Commit+ already connects to GitHub, GitLab, Bitbucket, and Azure DevOps for cloning, pushing, and pull requests, but users still switch to the browser to find the issue they are working on, retype its number into a branch name, or post a quick comment. The sidebar now has a dedicated ISSUES section (currently holding only Jira), so hosted issue trackers can join it without mixing integration data into the Workspace section.

## What Changes

- The sidebar ISSUES section gains one row for the repository's hosted issue tracker, labeled by provider: "GitHub Issues", "GitLab Issues", "Bitbucket Issues", or "Azure Boards". It appears only when one of the repository's remotes is recognized as one of these providers. Jira stays in the same section. The single "Show Issues" setting (General settings and the sidebar context menu) hides or shows the whole section.
- Selecting the row opens an issue list for that repository. By default it shows open issues from the repository's tracker. Azure Boards shows work items from the repository's project. Filters: state (open, closed, all), relationship (all, assigned to me, created by me), and text search. A remote picker appears when more than one remote has a supported tracker, for example a fork with an `upstream` remote. The filter and remote choice are remembered per repository.
- An issue detail pane shows the description, labels or tags, assignees, and comments, and offers: open in browser, copy number/key, copy reference with title, and create a branch from the issue (same flow as Jira, prefilled `<number>-<slug>`).
- Basic write actions: create an issue (title and description; on Azure, also the work item type), add a comment, and close or reopen an issue. Each write needs an explicit user action, is sent with the connected provider account, and refreshes the list and detail when it succeeds. Commit+ does not edit titles, descriptions, labels, assignees, or milestones, and does not delete issues.
- Gate the feature behind a new plan feature, `hostedIssues`, with the same rule as `pullRequests`: Free for public repositories, Pro for all repositories. When the remote policy is unavailable, the bundled rule applies.
- Provider coverage:
  - **GitHub**: GitHub.com and GitHub Enterprise Server.
  - **GitLab**: GitLab.com and self-managed GitLab.
  - **Bitbucket**: Bitbucket Cloud. The repository's issue tracker must be turned on, and the API token must include issue scopes.
  - **Azure Boards**: Azure DevOps Services work items. The PAT must include Work Items scope.

  When the tracker is turned off or the credential lacks the needed scope, the screen says so instead of showing an empty list.
- Azure Repos remotes now offer an issues link that opens the project's Boards work items page. Previously no issues link was offered.
- Out of scope: Repository AI tools for issues, linking commits or PRs to issues automatically, notifications, issue boards or iterations, editing issue fields, GitHub Projects, Bitbucket Data Center, Azure DevOps Server (on-premises), and offline caching beyond the session.

## Capabilities

### New Capabilities
- `repository-issues-section`: The sidebar ISSUES section. Covers which rows it contains (Jira and the hosted tracker row), when the hosted row appears and how it is labeled, the "Show Issues" setting, collapse state, and selection fallback when a row disappears.
- `hosted-issue-list`: The plan-gated hosted issue screen. Covers provider and remote resolution, access gating, connection and permission guidance, the list, filters, detail pane, and read-only actions including branch creation.
- `hosted-issue-actions`: Creating issues, commenting, and closing or reopening issues on the hosted tracker. Covers the required permissions, confirmation and error behavior, and the refresh that follows.

### Modified Capabilities
- `azure-repos-remote-recognition`: "Azure repositories open in the browser" changes from "no issues link" to an issues link that opens the project's Boards work items page.

## Impact

- **Native app (`macgit`)**:
  - New `PlanFeature.hostedIssues`, repository-scoped, with a bundled rule mirroring `pullRequests`.
  - A new `SidebarItem` for the hosted tracker row, with a provider-specific title.
  - A new per-window issue controller and four provider services (GitHub, GitLab, Bitbucket, Azure Boards) that reuse the existing provider accounts, `GitProviderTokenVault`, and remote identity resolution.
  - The branch-name suggester is generalized from Jira.
  - Updates to `MainWindowView` screen routing and gating, `RepositoryBookmarkRemote.issuesURL`, and the Bitbucket connect-sheet guidance (issue scopes).
- **External APIs**:
  - GitHub REST (`/repos/{owner}/{repo}/issues`, `/search/issues`, comments).
  - GitLab REST v4 (`/projects/:id/issues`, notes).
  - Bitbucket Cloud 2.0 (`/repositories/{workspace}/{slug}/issues`, comments).
  - Azure DevOps REST (WIQL, `workitemsbatch`, work item types and states, comments).
- **Synced settings**: none. "Show Issues" reuses the existing synced `showWorkspaceJira` field.
- **Cross-repository (`../landing-page`)**:
  - Add `hostedIssues` to the feature-policy schema (`admin/lib/schemas.ts`) and to the provisioning script (`scripts/firebase/set-feature-policy.mjs`, next revision). Until that policy is published, the app uses its bundled rule.
  - Publishing the policy requires explicit authorization.
  - No Firestore rules, indexes, or Cloud Functions change.
- **In-flight change `add-jira-sprint-issues`**: its requirement "Jira appears in the sidebar Workspace section" no longer matches the app. Placement is now defined by `repository-issues-section`, and that delta must be updated before either change is archived.
