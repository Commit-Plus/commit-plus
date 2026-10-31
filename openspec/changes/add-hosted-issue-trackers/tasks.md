# Tasks

## 1. ISSUES section and Show Issues setting (committed in 7dd65914)

- [x] 1.1 Add `SidebarSection.issues` with collapse state `issuesExpanded`, move `.jira` out of Workspace, and include both values in `SidebarNativeInput`. Verified by `SidebarViewStashTests` (collapse decode and toggle, Jira not in Workspace).
- [x] 1.2 Replace the per-row Jira toggle with `AppState.showIssues`, stored under the existing `showWorkspaceJira` key. Add "Show Issues" to General settings → Repository Sidebar and to the sidebar background menu. Verified by `AppSettingsSnapshotTests`, `CloudSettingsDocumentTests`, and `SidebarNativeListTests`.

## 2. Shared foundations

- [x] 2.1 Extract `matchingAccounts(for:)`, `apiCredential(for:)`, and token refresh from `PullRequestController` into `GitProviderAPICredentialResolver`, and switch `PullRequestController` to use it. Verify that `PullRequestControllerTests` still pass unchanged.
- [x] 2.2 Rename `JiraBranchNameSuggester` to `IssueBranchNameSuggester` and `JiraBranchTarget` to `IssueBranchTarget`. Change `prepareCreateBranch(from:target:)` to take `(key, summary)`. Verify that the renamed `IssueBranchNameSuggesterTests` pass, with an added case for a bare number key (`42-fix-login-on-safari`).
- [x] 2.3 Add `PlanFeature.hostedIssues` with a bundled rule equal to `.pullRequests`, add it to `requiresRepositoryScope`, and add its `FeatureAccessNotice` and upgrade-sheet text. Verify with `FeatureAccessPolicyTests` (bundled rule, missing remote entry, kill switch) and `FeatureAccessNoticeTests`.
- [x] 2.4 Add the `HostedIssue` models (summary, detail, comment, filter, state, page cursor, tracker capabilities), the `HostedIssueError` mapping, and the `HostedIssueProviding` protocol. Verify a `HostedIssueModelsTests` class for reference formatting (`#42` and `AB#42`) and filter persistence encoding.

## 3. Provider services (each with URLProtocol-stubbed unit tests)

- [x] 3.1 Implement `GitHubIssueService`: list, search, detail and comments, create, comment, close and reopen. Verify `GitHubIssueServiceTests`: PRs filtered out, `Link` pagination, assignee and creator filters, search query, `410` → `trackerDisabled`, org restriction → `organizationAccessRequired`, rate limit → `rateLimited`, and an Enterprise base URL.
- [x] 3.2 Implement `GitLabIssueService`. Verify `GitLabIssueServiceTests`: the state, scope, and search parameters, `X-Next-Page` pagination, `state_event` close and reopen, notes as comments, a self-managed host, and 403/404 mapping.
- [x] 3.3 Implement `BitbucketIssueService`. Verify `BitbucketIssueServiceTests`: the BBQL state and relationship query, `next` pagination, the open/closed state mapping, resolved/open transitions, no tracker → `trackerDisabled`, and 403 → `missingScope("issue")`.
- [x] 3.4 Implement `AzureBoardsWorkItemService`: WIQL, `workitemsbatch` chunking, the state-category map from the type states API, type list, create, comments, and close/reopen state selection. Verify `AzureBoardsWorkItemServiceTests`: the project-scoped WIQL with `@Me`, chunks of 200, Completed/Proposed state choice, a type with no Completed state → close unavailable, 401/403 → `missingScope("Work Items")`, and HTML description conversion that loads no remote content.

## 4. Controller and remote handling

- [x] 4.1 Implement `HostedIssueController`:
  - remote discovery (`origin` first, then other recognized remotes) and the remembered remote choice
  - per-repository and per-remote filter persistence in `LocalDataStore`
  - paged loading with a load-ID guard and a 60 s in-memory TTL
  - selection and detail
  - refresh when the screen becomes visible again after 60 s

  Verify `HostedIssueControllerTests` with a stub provider: default open filter, remembered remote and filter, stale responses dropped, no request when there is no account, and connect/reconnect states.
- [x] 4.2 Add the write flow: create, comment, close and reopen. Each write re-authorizes, keeps the draft on failure, never retries automatically, reloads detail and list on success, and keeps the written issue visible until the next refresh. Verify in `HostedIssueControllerTests`: the draft is kept after an error, the issue stays visible after closing under the Open filter, and a created issue is selected.
- [x] 4.3 Rediscover remotes on `.repositoryRemoteRefsDidRefresh` and `.repositoryDidChange` for the controller's own repository only. Verify in `HostedIssueControllerTests` that a notification for another repository URL is ignored and that adding a remote publishes a provider.

## 5. Sidebar row, routing, and gating

- [x] 5.1 Add `SidebarItem.hostedIssues` after `.jira` in `SidebarSection.issues.items`. Render it with the provider title and icon, add the provider to `SidebarNativeInput`, and omit the row when there is no recognized remote. Verify in `SidebarNativeListTests`: rows for GitHub/GitLab/Bitbucket/Azure titles, no row for a local-only repository, and a row rebuild when the provider changes.
- [x] 5.2 In `MainWindowView`, create `HostedIssueController` and add `authorizeHostedIssueAccess()` using `accessDecision(for: .hostedIssues)`. Add the cached screen block (allowed → view, denied → `FeatureAccessUnavailableView`, nil → progress). Reset the selection to File status when the provider becomes nil. Verify that the build succeeds and that the `RepositoryVisibilityControllerTests` case for `.hostedIssues` passes.
- [x] 5.3 Change `RepositoryBookmarkRemote.issuesURL` to return `https://dev.azure.com/{org}/{project}/_workitems` for Azure Repos. Verify with an updated `PullRequestURLBuilderTests` or bookmark remote test case for Azure.
- [x] 5.4 Add an optional "Atlassian email" field to the Bitbucket connect/edit sheet, saved as `GitProviderToken.apiUsername` in the Keychain only. Update the sheet guidance and the recorded scopes to include `read:issue:bitbucket` and `write:issue:bitbucket`. Verify in `GitProviderAccountControllerTests` that the email is saved with the token and is absent from the synced account, and that a token saved without it still decodes.

## 6. Views

- [x] 6.1 Build `HostedIssueListView`: filter bar, remote picker shown only with more than one tracker, rows, infinite scroll, and empty, filtered-empty, disabled-tracker, missing-scope, org-access, rate-limited, and error states, with Retry. Verify that the build succeeds.
- [x] 6.2 Build `HostedIssueDetailView`: metadata, Markdown body through `PullRequestMarkdownContent`, Azure plain-text body, comments, the comment composer, Close/Reopen, open in browser, copy number, copy reference, and the create-branch menu (plain branch and Git Flow targets). Verify that the build succeeds.
- [x] 6.3 Build `NewHostedIssueSheet`: required title, Markdown description, and an Azure type picker; Create disabled while blank or in flight. Verify that the build succeeds.

## 7. Integration checks

- [x] 7.1 Run `xcodebuild … -only-testing:macgitTests/GitHubIssueServiceTests -only-testing:macgitTests/GitLabIssueServiceTests -only-testing:macgitTests/BitbucketIssueServiceTests -only-testing:macgitTests/AzureBoardsWorkItemServiceTests -only-testing:macgitTests/HostedIssueControllerTests -only-testing:macgitTests/HostedIssueModelsTests -only-testing:macgitTests/IssueBranchNameSuggesterTests -only-testing:macgitTests/PullRequestControllerTests -only-testing:macgitTests/FeatureAccessPolicyTests -only-testing:macgitTests/FeatureAccessNoticeTests -only-testing:macgitTests/RepositoryVisibilityControllerTests -only-testing:macgitTests/SidebarNativeListTests -only-testing:macgitTests/SidebarViewStashTests -only-testing:macgitTests/JiraIssueListControllerTests test` and confirm that all tests pass.
- [ ] 7.2 Manual UI review in the running app:
  - the ISSUES section with Jira and a hosted row for a GitHub, a GitLab, a Bitbucket, and an Azure repository
  - collapse and Show Issues
  - the remote picker on a fork
  - list and detail layout at narrow and wide window sizes
  - create, comment, close and reopen on a test repository
  - a missing-scope message for a Bitbucket token without issue scopes and an Azure PAT without Work Items
  - Free-plan gating on a private repository

  Record anything not checked.
- [x] 7.3 Update the `add-jira-sprint-issues` delta so its Workspace placement requirement defers to `repository-issues-section`, and run `openspec validate add-jira-sprint-issues` and `openspec validate add-hosted-issue-trackers`.
- [x] 7.4 Run `git diff --check` and confirm there is no output.

## 8. Cross-repository rollout (`../landing-page`)

- [ ] 8.1 Add `hostedIssues` to `admin/lib/schemas.ts` and to the next revision of `scripts/firebase/set-feature-policy.mjs`, with the same rule as `pullRequests`. Verify that the repository's own build and type check pass, per its `AGENTS.md`, without running emulator tests.
- [ ] 8.2 Publish the updated feature policy to production only after explicit user authorization. Verify CLI success for the intended project, and report separately what is local, committed, pushed, and published.

## Workflow follow-up

- Archive this change with `/opsx:archive` after implementation and validation, after `add-jira-sprint-issues` has been reconciled.
