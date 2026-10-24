# Proposal

## Why

Developers using Commit+ track their sprint work in Jira and switch to the browser to see what they are assigned, then retype issue keys into branch names. A focused Jira issue list inside the repository window, limited to the user's own issues and filterable by sprint, removes that context switch and is a natural Commit+ Pro capability.

## What Changes

- Add a Jira Cloud connection in Settings → Integrations using the user's site URL, Atlassian account email, and an Atlassian API token. This mirrors the existing Bitbucket connection, which also uses an Atlassian API token (it is not OAuth). A Bitbucket token cannot be reused: Jira needs its own token with Jira access. The connection is stored on this Mac only (metadata locally, token in the Keychain) and is not synced through Firebase.
- Add a "Jira" item to the sidebar Workspace section, which the user can hide from "Customize Workspace" like Reflog, Pull Requests, and Git LFS.
- Selecting it opens a Jira issues screen: a flat list (no board) of issues assigned to the connected user, defaulting to issues in open sprints that are not done.
- Filters: sprint (open sprints, a specific sprint, backlog, or any), status category, project, issue type, and text search on key or summary. The filter is remembered per repository.
- Issue actions: open in Jira, copy key, copy key and summary, and create a branch from the issue. Branch creation prefills a name from the issue key and summary and uses the existing Git Flow start sheet when Git Flow is configured, otherwise the existing branch sheet. Nothing is written to Jira.
- Gate the screen behind a new Pro-only plan feature, `jiraIssues`. Free and signed-out users see the existing feature-access/upgrade view instead of the list.
- Out of scope: OAuth (3LO), Jira Data Center/Server, editing or transitioning issues, boards, multiple Jira sites, cloud sync of the connection, and Repository AI tools for Jira.

## Capabilities

### New Capabilities
- `jira-account-connection`: Connecting, validating, reconnecting, and removing a Jira Cloud site with an Atlassian API token in Settings → Integrations, and keeping the credential local to this Mac.
- `jira-issue-list`: The Pro-gated Jira item in the sidebar Workspace section and its issue list screen: which issues are shown, filtering, loading/error/empty states, and per-issue actions including creating a branch from an issue.

### Modified Capabilities
<!-- None: no existing spec covers the sidebar Workspace items or plan feature keys. -->

## Impact

- **Native app (`macgit`)**: new `PlanFeature.jiraIssues` with a Pro-only bundled rule; new Jira client, connection controller, Keychain token store, and issue list controller; `SidebarItem`, `SidebarSection`, `WorkspaceVisibilityPopover`, `AppState` (visibility toggle), `MainWindowView` (screen routing and gating), `IntegrationsSettingsView`, `ProUpgradeSheet`/feature display names, and branch/Git Flow start sheets (prefilled name).
- **External API**: Jira Cloud REST API v3 (`/rest/api/3/myself`, `/rest/api/3/search/jql`, `/rest/api/3/field`, `/rest/api/3/project/search`) over HTTPS with Basic auth.
- **Synced settings**: the new `showWorkspaceJira` toggle is a `CloudSettingsDocument` field, like the other Workspace toggles.
- **Cross-repository (`../landing-page`)**:
  - `firestore.rules` `validAppSettings` must allow `showWorkspaceJira` as a bool. These rules must be deployed before the app version ships, because otherwise production rejects the whole settings document.
  - Add `jiraIssues` to the feature-policy schema (`admin/lib/schemas.ts`) and provisioning script (`scripts/firebase/set-feature-policy.mjs`, next revision). Until that policy is published, the app uses its bundled Pro-only rule.
  - Both deployments require explicit authorization. No indexes or Cloud Functions change, and the Jira connection itself is never written to Firestore.
