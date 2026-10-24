# Design

## Context

See proposal.md for motivation and specs/ for required behavior. Current state that shapes the approach:

- **Workspace items.** `SidebarItem` lists the Workspace screens, and `SidebarSection.workspace.items` orders them. `SidebarView+NativeRows.swift` filters them with `AppState` toggles (`showWorkspaceReflog`, `showWorkspacePullRequests`, `showWorkspaceGitLFS`, `showGitFlow`), which `WorkspaceVisibilityPopover` edits. Those toggles are `AppSettingsSnapshot` fields, are encoded by `CloudSettingsDocument` (`FirestoreSettingsStore.swift`), and are allowlisted in `validAppSettings` in `../landing-page/firestore.rules`.
- **Gated screens.** `MainWindowView.cachedRepositoryScreens` keeps the Pull Requests screen alive once opened (`hasOpenedPullRequests` plus `.repositoryScreenVisibility`). It switches on a `FeatureAccessDecision` to show `PullRequestListView`, `FeatureAccessUnavailableView`, or a progress view, and re-evaluates access through a task keyed on policy revision, entitlement, and selection (`pullRequestAccessTaskID`). `ProUpgradeSheet` and `FeatureAccessNotice` switch exhaustively over `PlanFeature`.
- **Feature policy.** `FeatureAccessPolicy.bundled` (revision 7) is the local fallback. `FeaturePolicyStore` decodes each `PlanFeature` independently and falls back to the bundled entry when a key is missing, so the app can ship a new key before the remote policy has it.
- **Atlassian credentials today.** `GitProviderAccountController.connectBitbucket` stores a Bitbucket username plus an Atlassian API token through `GitProviderTokenVault` (Keychain), and the account metadata syncs through `FirestoreGitProviderAccountStore`. Its `provider` is limited by `firestore.rules` to Git hosts. GitHub/GitLab OAuth (`GitProviderOAuthModels`, the `macgit://git-provider` callback, and the commitplus.app token exchange) is Git-provider specific.
- **Branch creation.** `BranchSheetView` creates branches through `GitStatusService.createBranch`, registers undo (`deleteLocalBranch` with `expectedTip`), and its `onCompleted` refreshes `SyncState` and posts `.repositoryDidChange`. `StartGitFlowSheet` builds a `GitFlowStartPlan` from a typed `topicName` and calls `MainWindowView.startGitFlow`.
- **Local persistence.** Non-secret local state uses `LocalDataStore` collections (for example `providerPreferences`).

## Goals / Non-Goals

**Goals:**
- Reuse the existing gating, sidebar, sheet, and refresh flows so the Jira screen behaves like Pull Requests from the user's point of view.
- Keep every Jira request and credential on the Mac. Add no new backend service and change no Firebase contract except the settings toggle and the feature-policy key.
- Make the Jira client testable without network access.

**Non-Goals:**
- A generic issue-tracker abstraction (Linear, GitHub Issues, and others). The Jira types are concrete. Generalize only when a second tracker exists.
- Linking issues to commits or branches after creation, smart commits, or showing Jira data in History.
- Background polling or notifications for Jira changes.

## Decisions

### 1. A separate `JiraConnectionController`, not a new `GitProviderKind`
Add an app-level `@MainActor final class JiraConnectionController: ObservableObject` in `macgit/App/`. Create it in `macgitApp` next to `providerAccountController`, inject it as an environment object, and update it with the signed-in `macgitUID` when the Commit+ account changes, the same way `providerAccountController.updateMacgitAccount` is driven.

- *Why not extend `GitProviderAccountController` / `GitProviderKind`:* Jira is not a Git host. Adding a case would force every exhaustive switch (remote recognition, credential injection, PR services, SSH) to handle a provider that has no remotes. It would also sync the account through `FirestoreGitProviderAccountStore`, whose rules reject unknown providers. Decision: share only the Keychain and HTTP patterns.
- Storage:
  - The token goes in a new `KeychainJiraTokenStore`, modeled on `KeychainGitProviderTokenVault`: service `com.commitplus.macgit.jira-tokens`, account key `<macgitUID>:<siteHost>:<accountID>`, with the same in-memory cache approach.
  - Non-secret metadata (site URL, email, Jira `accountId`, display name, status, whether the connection needs reconnection) goes in the `LocalDataStore` collection `jiraConnections`, keyed by `macgitUID`.
- Behavior follows `connectBitbucket`: validate first, then save metadata and token together, and roll back the token if the metadata write fails. Reconnect verifies the new token before replacing the old one. Remove deletes both.

- Settings UI: Jira is its own section in Settings → Integrations (`JiraIntegrationSection`), not part of the Connections account list. That list, its add-account sheet, and the multiple-account limit are typed to `GitProviderAccount`. Adding a non-Git account would mix Jira into the Free account-count gate and the Git editor panel. The Jira screen's "Connect Jira" and "Open Jira Settings" actions call `AccountSessionController.presentIntegrations()`.

### 2. API token over Basic auth against the site URL
Authenticate with `Authorization: Basic base64(email:token)` against `https://<site>.atlassian.net`. Validate with `GET /rest/api/3/myself`, which returns `accountId`, `displayName`, and `emailAddress`.

- *Alternative, OAuth 2.0 (3LO):* rejected for this change by user decision. Atlassian requires a client secret for code exchange and for rotating refresh, so it needs new commitplus.app routes, an Atlassian developer app, and backend deployment. The client is structured so a later OAuth credential can replace the Basic header: `JiraCloudClient` takes a credential value, not raw strings.
- *Scoped API tokens:* Atlassian's newer scoped tokens must be sent through `https://api.atlassian.com/ex/jira/<cloudId>`. At connect time, resolve `cloudId` from `https://<site>/_edge/tenant_info`, try the site URL first, and on 401 retry `/myself` through the gateway. Store which base worked (`apiBase: site | gateway`) with the connection. The connect form tells users which read scopes a scoped token needs (`read:jira-work`, `read:jira-user`).
- Site validation is done before any request: HTTPS only, and the host must end in `.atlassian.net`. A bare name expands to `https://<name>.atlassian.net`. This prevents sending the token to an arbitrary host.

### 3. `JiraCloudClient` as a plain service, outside `GitStatusService`
Add `macgit/Services/JiraCloudClient.swift`, a `Sendable` struct that takes `GitProviderHTTPClient`, the existing HTTP seam (renaming it is out of scope). It is not git work, so it does not belong in `GitStatusService`.

- **Search:** `POST /rest/api/3/search/jql` with `nextPageToken` pagination (the older `/rest/api/3/search` is deprecated). Request only the fields the list needs: `summary`, `status`, `issuetype`, `priority`, `project`, `updated`, and the sprint field. Page size is 50.
- **Sprint field:** Jira stores sprints in a custom field. Discover its id once per connection from `GET /rest/api/3/field`, where the schema custom type is `com.pyxis.greenhopper.jira:gh-sprint`, and cache it with the connection metadata. If it is missing (a site without Jira Software), hide the sprint filter, and the default query drops the sprint clause.
- **Error mapping:** 401 → `needsReconnect`; 403 → no permission; 429 → rate limited, honoring `Retry-After` for the Retry message; 5xx or a network failure → unreachable. Error messages never include request headers or the response body verbatim.

### 4. JQL is built from a typed filter, never from free text
`JiraIssueFilter` (Codable) holds the sprint scope (`openSprints | sprint(id) | backlog | any`), a status-category set, a project key set, an issue type id set, and an optional search text. `JiraJQLBuilder` turns it into JQL:

- It always starts with `assignee = currentUser()`.
- The sprint scope becomes `sprint in openSprints()`, `sprint = <id>`, `sprint is EMPTY`, or nothing.
- The other parts are `statusCategory in (...)`, `project in (...)`, `issuetype in (...)`, and `ORDER BY updated DESC`.
- Search text becomes `(text ~ "<escaped>" OR key = "<KEY>")`, with the key clause used only when the text matches `^[A-Z][A-Z0-9_]+-\d+$`.
- Values are quoted and escaped, so a crafted search string cannot change the query.

The default filter is open sprints with status categories To Do and In Progress.

Sprint and project filter options are derived from the issues loaded with the current non-sprint, non-project constraints, plus the remembered selection. This avoids the Agile board API, which needs board ids the user does not have. Trade-off: a sprint with no issues assigned to the user is not offered, which is acceptable because the list only shows their own issues.

### 5. Per-window `JiraIssueListController`, owned by `MainWindowView`
Add `@MainActor final class JiraIssueListController: ObservableObject` in `macgit/App/`, shaped like `PullRequestController`: `items`, `isLoading`, `hasLoadedList`, `errorState`, `nextPageToken`, `filter`, and `searchText`. `MainWindowView` creates it as a `@StateObject` next to `pullRequestController`, so each repository window has its own instance and its own filter.

- Loads are generation-guarded, like `SyncState`: a filter change cancels the in-flight task, and late results are dropped. Rows are kept during refresh. Search text is debounced (300 ms).
- Filters are persisted per repository in the `LocalDataStore` collection `jiraIssueFilters`, keyed by the standardized repository path, excluding `searchText`. A missing or undecodable value falls back to the default.
- The controller reads the connection from `JiraConnectionController` and observes it, so connect, reconnect, and remove in Settings update open windows without a relaunch.

### 6. Gating mirrors Pull Requests
- Add `PlanFeature.jiraIssues` with the bundled rule `proOnlyRule`. Bump the bundled revision to 8 and set `requiresRepositoryScope` to `false`.
- Add the display name "Jira Issues" to `ProUpgradeSheet.upgradeDescription` (in the non-scoped group) and to `FeatureAccessNotice`.
- In `MainWindowView`, add `jiraAccessDecision` and `jiraAccessTaskID`, built the same way as the Pull Requests versions. Add a `hasOpenedJira` branch in `cachedRepositoryScreens` that shows `JiraIssueListView` when allowed, `FeatureAccessUnavailableView(feature: .jiraIssues, …)` when denied, and a progress view while the decision is unknown.
- The `body` switch returns `EmptyView()` for `.item(.jira)`, as it does for `.pullRequests`.
- The controller never loads unless the decision is `.allowed`, which satisfies "no Jira request when denied".

### 7. Sidebar and visibility toggle
- Add `SidebarItem.jira = "Jira"` with SF Symbol `checklist`, inserted in `SidebarSection.workspace.items` after `.pullRequests`.
- Add `AppState.showWorkspaceJira` (default `true`) through the full settings path: `AppSettingsSnapshot` (with `decodeIfPresent ?? true`), `CloudSettingsDocument` encode and decode, `AppState` load, apply, and snapshot, and a toggle in `WorkspaceVisibilityPopover`.
- When the toggle turns off while `.item(.jira)` is selected, `MainWindowView` selects `.item(.fileStatus)`. Implement this in an `onChange` of `appState.showWorkspaceJira`. No existing toggle does this, so it is new behavior scoped to Jira.
- Row context menu: none for v1. Actions live on the issue rows.

### 8. Branch from issue reuses existing sheets
- `JiraBranchNameSuggester` builds the name `<KEY>-<slug>`. The slug is the summary folded to ASCII (`applyingTransform(.toLatin)` then `.stripDiacritics`), lowercased, with runs of characters outside `[a-z0-9]` replaced by a single `-`, and trimmed. The whole name is limited to 60 characters at a hyphen boundary, and the key is always kept.
- `BranchSheetView` gets an optional `initialBranchName` parameter that seeds its name field. `StartGitFlowSheet` gets an optional `initialTopicName` parameter that seeds `topicName`. Both default to `nil`, so existing call sites are unchanged.
- `JiraBranchTarget` (`plainBranch` or `gitFlow(kind)`) describes the choice. `suggested(forIssueType:gitFlowEnabled:)` maps Bug/Defect to bugfix and everything else to feature. `options` offers feature, bugfix, hotfix, and a plain branch; release is excluded because its name is a version.
- `JiraIssueListView` calls back to `MainWindowView` (`prepareCreateBranch(from:target:)`). `MainWindowView` presents `startGitFlowSheet(for: kind, initialTopicName:)` for a Git Flow target when `gitFlowConfiguration` is enabled, otherwise `branchSheet(startPoint: nil, initialBranchName:)`.
- Details panel: single-clicking a row shows `JiraIssueDetailPanel` in an `HSplitView` beside the list. It uses only fields already returned by the search (no extra request) and repeats the context-menu actions, with a split button whose default is the suggested branch target. It goes through the existing sheet presentation state, so undo registration, `SyncState.refresh`, and `.repositoryDidChange` come from the existing sheets with no new mutation code.

### 9. Window scoping
This change adds no menu-bar commands, toolbar items, or `NotificationCenter` routes. Refresh, filter, open, copy, and create-branch actions are buttons and context-menu items inside the Jira view of one window, and their callbacks go to that window's `MainWindowView`. Connection changes reach all windows through the shared `JiraConnectionController`, which is intended because the connection is app-wide. If a later change adds a "Refresh Jira" menu command, it must use `WindowScopedNotification.post` like the other repository commands.

### 10. Repository AI
Not exposed. No Jira tool is added to `RepositoryAIAgentHarness`, and the Jira token is never available to model context.

## Risks / Trade-offs

- [Scoped API tokens need the `api.atlassian.com` gateway, and Atlassian is moving users toward them] → Detect at connect time and store `apiBase`. Cover both paths with HTTP stub tests. If verification shows classic tokens also work through the gateway, simplify to gateway-only.
- [`/rest/api/3/search/jql` pagination differs from the old endpoint (no `total`, token-based)] → The UI shows only "load more" behavior and never a total count.
- [Sprint options come only from loaded issues] → This is documented in the spec ("from those the user's issues belong to"). The Agile API is a later improvement.
- [Adding `showWorkspaceJira` to the cloud settings document] → If the app ships before the updated `validAppSettings` rules are deployed, every settings write from that version is rejected. Mitigation: the rules deployment is an explicit rollout step that must come before the release (see Migration Plan).
- [Rate limits on large Jira sites] → No polling. Load on open, on filter change, and on Refresh only. Back off on 429 using `Retry-After`.
- [Token stored per Mac, not synced] → Users connect once per Mac. This is the intended privacy property and is stated in the spec.

## Migration Plan

1. **landing-page, before the app release:** allow `showWorkspaceJira` (bool) in `validAppSettings`, run that repository's non-emulator checks, and, with explicit authorization, deploy **Firestore rules only** to the production project.
2. **landing-page:** add `jiraIssues` to `admin/lib/schemas.ts` `featureKeys` (non-scoped) and to `scripts/firebase/set-feature-policy.mjs` as `proOnly`, at revision 8. With explicit authorization, publish the release feature policy. This can happen before or after the app release, because the bundled fallback is also Pro-only.
3. Release the macOS app.
4. **Rollback:** hide the screen for everyone by publishing `jiraIssues.enabled = false`. The rules change is additive and does not need a rollback.

## Open Questions

- Whether classic (unscoped) API tokens work through the `api.atlassian.com` gateway. This decides whether the site-first fallback can be removed later, but it does not change the specs or tasks.
