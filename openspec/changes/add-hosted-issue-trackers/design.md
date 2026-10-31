# Design

## Context

- The ISSUES sidebar section, the single `AppState.showIssues` setting (persisted under the existing `showWorkspaceJira` UserDefaults and Firestore key), and its collapse state (`SidebarSectionState.issuesExpanded`) are already in the working tree. The work that remains is the hosted tracker row and everything behind it.
- Pull requests already solve the problems issues need solved:
  - `GitRemoteIdentityResolver` maps a remote URL to a `GitRepositoryIdentity` (provider, host, owner, name).
  - `PullRequestController` picks the remote (`origin`, else the first), finds matching `GitProviderAccount`s by provider and host, and obtains a fresh `GitProviderToken` from `GitProviderTokenVault`. That account-matching and credential-resolution logic is private to `PullRequestController`.
  - Each provider has a stateless `*PullRequestService: PullRequestProviding`.
  - `RepositoryVisibilityController.accessDecision(for:)` combines the policy, entitlement, and repository visibility.
  - Markdown renders through `PullRequestMarkdownContent`.
- Jira contributes the screen shape:
  - `JiraIssueListController` handles per-repository filter persistence through `LocalDataStore` and paged loading.
  - `JiraBranchNameSuggester` builds the branch name.
  - `MainWindowView.prepareCreateBranch(from:target:)` opens the branch or Git Flow start sheet.
- Provider credentials today:
  - GitHub OAuth has the `repo` scope and GitLab has `api`. Both already cover reading and writing issues.
  - Bitbucket API tokens are created with only the repository scopes.
  - Azure PATs are validated with any scope (`connectionData`).

  So Bitbucket and Azure can fail with a permission error even for a connected account.
- There is no Bitbucket visibility service, so `RepositoryVisibilityController` reports `.unknown` for Bitbucket remotes.

## Goals / Non-Goals

**Goals:**
- One controller and view serve all four providers. Provider differences live in services and in a small capability description.
- Reuse the provider-account matching and token refresh used by pull requests, without copying it.
- Every provider error maps to a typed error the view can explain (see `hosted-issue-list` and `hosted-issue-actions` specs).

**Non-Goals:**
- Changing how pull requests resolve accounts, beyond extracting the shared helper.
- A Bitbucket repository-visibility service. Free users on Bitbucket remotes get the same `repositoryVisibilityUnavailable` outcome as other visibility-gated features.
- Disk caching of issues. An in-memory cache per window is enough.

## Decisions

### 1. Extract provider credential resolution from `PullRequestController`
Move `matchingAccounts(for:)`, `apiCredential(for:)`, and the token refresh path into `GitProviderAPICredentialResolver`, a `@MainActor` struct initialized with `GitProviderAccountController` and `GitProviderTokenVault`. Both `PullRequestController` and the new issue controller call it. This also gives both features the same reconnect and connect messaging.
- *Alternative:* have the issue controller call into `PullRequestController`. Rejected because it ties the issue screen to the PR screen's lifecycle and published state.
- *Alternative:* duplicate the logic. Rejected because token refresh and account selection would drift apart.

### 2. `HostedIssueProviding` protocol plus four stateless services
Mirror `PullRequestProviding`. The protocol has these operations:
- `capabilities(repository:token:)` returns the tracker's capabilities: enabled or disabled, work item types, and the state map.
- `listIssues(repository:token:filter:cursor:)` returns a page of results.
- `issueDetail`
- `createIssue`
- `addComment`
- `setState(open|closed)`

Each service owns its provider details:

| Provider | List | Filters | Pagination | Notes |
|---|---|---|---|---|
| GitHub (`GitHubIssueService`) | `/repos/{o}/{r}/issues` | `state`, `assignee=<login>`, `creator=<login>` | `Link` header | Drops items that have `pull_request`. When search text is present it uses `/search/issues?q=repo:o/r is:issue …`, which has its own rate limit. The base URL comes from the account host, so GitHub Enterprise Server works. `410 Gone` means issues are disabled. |
| GitLab (`GitLabIssueService`) | `/projects/:id/issues` | `state=opened\|closed`, `scope=assigned_to_me\|created_by_me\|all`, `search=` | `page` and `per_page` (`X-Next-Page`) | Close and reopen use `state_event`. Comments are notes. |
| Bitbucket (`BitbucketIssueService`) | `/2.0/repositories/{ws}/{slug}/issues` | BBQL `q=` with `state IN (...)`, `assignee.uuid=` and `reporter.uuid=` | The `next` URL | Open means `new`, `open`, or `on hold`. Closed means any other state. Close and reopen set `resolved` and `open`. A 404 with "no issue tracker" means disabled. 403 means a missing `read:issue:bitbucket` or `write:issue:bitbucket` scope. |
| Azure Boards (`AzureBoardsWorkItemService`) | WIQL scoped to `[System.TeamProject]`, with `@Me` for assigned or created | — | IDs come in one WIQL response, then details are fetched with `workitemsbatch` in chunks of 200. Pagination works over the ID list. | Before filtering by state, it calls `workitemtypes/{type}/states` to map states to categories. Open means Proposed, InProgress, or Resolved. Closed means Completed or Removed. Close moves to the first Completed state and Reopen to the first Proposed state. Comments use the work item comments API (preview version pinned). Descriptions are HTML. |

Each service maps provider errors to `HostedIssueError`:
- `trackerDisabled`
- `missingScope(String)`
- `organizationAccessRequired`
- `reauthorizationRequired`
- `rateLimited(retryAfter:)`
- `notFound`
- `providerMessage`
- *Alternative:* add issue methods to `PullRequestProviding`. Rejected because the two features have different lifecycles and Bitbucket has no PR service.

### 3. `HostedIssueController`: one per window, owned by `MainWindowView`
`HostedIssueController` is a `@MainActor ObservableObject` created next to `PullRequestController` and `JiraIssueListController` in `MainWindowView.init`. It owns:
- remote discovery (recognized remotes and the chosen remote)
- filter state
- paged items
- selection and detail
- the write-in-progress state
- an in-memory list cache with a 60 s TTL

Filters and the chosen remote are persisted through a `LocalDataStore` collection keyed by repository path. Filters are additionally keyed by remote name. This follows `LocalJiraIssueFilterStore`. Loads use a load-ID guard, the same pattern as `PullRequestController`, so stale responses are dropped. After a successful write, it reloads detail and the current page, keeps the selection, and marks the written issue as pinned until the next refresh.
- The controller listens for `.repositoryRemoteRefsDidRefresh` and `.repositoryDidChange` for its own repository URL to rediscover remotes. These notifications already carry the repository; the controller ignores other repositories, so the behavior is window-scoped.

### 4. Sidebar row: one `SidebarItem.hostedIssues` with a dynamic title
Add `SidebarItem.hostedIssues` to `SidebarSection.issues.items` after `.jira`. Today `SidebarView+NativeRows` uses `item.rawValue` as the title. For the issues section it will take the title and icon from `HostedIssueProvider` (derived from the chosen remote's `GitProviderKind`), which `SidebarView` receives as an input. That value is also added to `SidebarNativeInput.flags`/a new field, so the row rebuilds when it changes. This avoids the bug fixed earlier, where a missing input left the list stale. The row is omitted when no remote is recognized. `MainWindowView` already resets the selection on `showIssues` changes; extend that `onChange` so it also resets when the provider becomes nil.
- *Alternative:* one `SidebarItem` case per provider. Rejected because selection, routing, and screen caching would need four identical cases.

### 5. Gating: `PlanFeature.hostedIssues`, repository-scoped
- Add the case to `PlanFeature`.
- Give it a bundled rule identical to `.pullRequests`: Free `.public`, Pro `.all`.
- Add it to `requiresRepositoryScope` in `FeaturePolicyStore`.
- Add display text in `FeatureAccessNotice` and the Pro upgrade sheet.

`MainWindowView` gets `authorizeHostedIssueAccess()`, mirroring `authorizePullRequestAccess()` through `repositoryVisibilityController.accessDecision(for: .hostedIssues, …)`. The screen block in `cachedRepositoryScreens` follows the pull request block: allowed shows the view, denied shows `FeatureAccessUnavailableView`, and nil shows progress. Write actions call the same authorization again before sending.

### 6. Views
- `Views/Issues/HostedIssueListView` is a split view: a list with a filter bar and a remote picker, next to a detail pane.
- `HostedIssueDetailView` reuses `PullRequestMarkdownContent` and the conversation block styling.
- `NewHostedIssueSheet` holds the title, description, and (Azure only) the type picker.

Azure HTML is converted to plain text with `NSAttributedString(html:)` options that disable remote resource loading, or a stripping fallback if needed. It is never shown in a web view. "New Issue…" is a button in the screen's toolbar, not a menu command, so no `FocusedValues` or notification routing is added.

### 7. Branch naming
Rename `JiraBranchNameSuggester` to `IssueBranchNameSuggester`. Its `name(key:summary:)` stays as it is, and hosted issues pass the bare number as `key`. Rename `JiraBranchTarget` to `IssueBranchTarget`. `prepareCreateBranch(from:target:)` takes `(key, summary)` so Jira and hosted issues share it.

### 8. Undo and refresh
Issue writes do not touch the repository, so they are not registered with `GitUndoManager` and do not go through `SyncState`. Refresh after a write is local to `HostedIssueController`, as the `hosted-issue-actions` spec describes.

### 9. Bitbucket connection: Atlassian email and issue scopes
Bitbucket REST calls authenticate an API token with HTTP Basic `email:token`. The Git username stored on the account does not work for REST, and the app made no Bitbucket REST calls before this change.
- Add an optional `apiUsername` field to `GitProviderToken`. It is optional and `Codable`, so existing Keychain items still decode. It is filled from a new "Atlassian email" field in the Bitbucket section of `GitProviderAddAccountSheet` and passed through `GitProviderAccountController.connectBitbucket`.
- Keeping the email in the Keychain token, rather than in `GitProviderAccount.permissions`, keeps it off Firestore. Provider-account sync stores `permissions` as a synced map.
- When a Bitbucket token has no `apiUsername`, `BitbucketIssueService` throws `HostedIssueError.accountUpdateRequired`, and the screen offers Settings → Connections.
- Update the connect sheet text to list the issue scopes (`read:issue:bitbucket`, `write:issue:bitbucket`) and add them to the scopes recorded for new connections. Existing tokens keep working for Git and hit `accountUpdateRequired` or `missingScope` only on the issue screen.

## Risks / Trade-offs

- [GitHub search API limit (30 requests/min) when searching] → Debounce search by 400 ms and search only on server-side text input. On `rateLimited`, show the retry time.
- [The Azure comments API is a preview version] → Pin the version in one place. On a 400 or 404 from that endpoint, show the comments as unavailable instead of failing the whole detail.
- [Azure state categories differ per process template] → Read them from the states API for each type and cache them for the session. Never hard-code names like "Closed" or "Done".
- [Bitbucket issue trackers are often turned off] → The `trackerDisabled` state explains this and links to the repository settings page.
- [Free users on Bitbucket remotes are denied because visibility is unknown] → This matches existing visibility-gated features. Note it as a follow-up (a Bitbucket visibility service), not a blocker.
- [`hostedIssues` missing from the published policy] → The bundled rule applies. Publishing the policy is a separate authorized rollout step.
- [GitHub Enterprise or self-managed GitLab running old API versions] → Use only long-stable v3/v4 endpoints, and surface `providerMessage` as is.

## Migration Plan

1. Ship the app with the bundled `hostedIssues` rule. No settings or data migration is needed; "Show Issues" already reuses the synced key.
2. In `../landing-page`, add `hostedIssues` to `admin/lib/schemas.ts` and `scripts/firebase/set-feature-policy.mjs` (next revision, same rule as `pullRequests`). Publish the policy only with explicit user authorization.
3. Update the `add-jira-sprint-issues` delta so it defers placement to `repository-issues-section` before archiving either change.
4. Rollback: a remote policy entry `hostedIssues.enabled = false` hides the feature without an app update.
