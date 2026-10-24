# Tasks

## 1. Plan feature and gating fallback

- [x] 1.1 Add `PlanFeature.jiraIssues`. Give it `proOnlyRule` in `FeatureAccessPolicy.bundled`, bump the bundled revision to 8, and add it to the non-scoped group in `FeaturePolicyStore.requiresRepositoryScope`. Verify with new `FeatureAccessPolicyTests` cases: Pro is allowed, Free is denied, a remote policy without the key falls back to the bundled entry, and a remote `enabled: false` disables it.
- [x] 1.2 Add the "Jira Issues" display name and copy to `ProUpgradeSheet.upgradeDescription` and `FeatureAccessNotice`. Verify with a `FeatureAccessNoticeTests` case for `.jiraIssues` (signed out and Free).

## 2. Jira Cloud client

- [x] 2.1 Add the Jira models (`JiraConnection`, `JiraIssue`, `JiraIssueFilter`, `JiraSprintRef`, and the error enum) and the site normalizer: HTTPS only, `*.atlassian.net` only, bare names expand to `https://<name>.atlassian.net`. Verify with `JiraSiteNormalizerTests` covering accepted, expanded, and rejected inputs.
- [x] 2.2 Add `JiraJQLBuilder` as described in design §4: always `assignee = currentUser()`, the sprint scopes, status categories, projects, types, escaped search text, and the key-match clause. Verify with `JiraJQLBuilderTests`, including quote, backslash, and JQL-keyword injection attempts in the search text.
- [x] 2.3 Add `JiraCloudClient` on top of `GitProviderHTTPClient`:
  - `/myself` validation with the site-then-gateway fallback (`_edge/tenant_info` → `cloudId`)
  - sprint field discovery through `/rest/api/3/field`
  - `POST /rest/api/3/search/jql` with `nextPageToken` pagination and a fixed field list
  - status error mapping: 401, 403, 429 with `Retry-After`, 5xx, and network failures

  Verify with `JiraCloudClientTests` using a stub HTTP client. The tests must assert the Basic header format, that no token appears in any error description, and that a missing sprint field disables sprint filtering.

## 3. Connection storage and controller

- [x] 3.1 Add `KeychainJiraTokenStore` (service `com.commitplus.macgit.jira-tokens`, key `<macgitUID>:<host>:<accountId>`) behind a protocol with an in-memory test double, and store connection metadata in the `LocalDataStore` collection `jiraConnections`, keyed by `macgitUID`. Verify with `JiraConnectionStoreTests` using a temporary `LocalDataStore`: save, load, and remove, and confirm that a different `macgitUID` cannot see the connection.
- [x] 3.2 Add `JiraConnectionController` (`@MainActor`, app-level). Create it in `macgitApp`, inject it as an environment object, and drive it from the signed-in account. It needs connect (validate, then save, rolling back the token if the metadata write fails), reconnect (verify, then replace), remove, and mark-needs-reconnect on 401. Verify with `JiraConnectionControllerTests`: a rejected token saves nothing, an invalid reconnect leaves the old token, remove deletes both stores, and a signed-out state cannot connect.

## 4. Settings → Integrations UI

- [x] 4.1 Add a Jira section to `IntegrationsSettingsView`, styled like its other grouped sections (status rows plus a `SettingsActionRow`):
  - Connect form with site, email, token, a link to Atlassian's API token page, and the scoped-token scope hint
  - Connected row showing name, email, and site, with Reconnect and Remove
  - Remove confirmation stating that the token is not revoked at Atlassian
  - Sign In shown when signed out

  Verify with a build: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.

## 5. Sidebar item and synced visibility toggle

- [x] 5.1 Add `SidebarItem.jira` ("Jira", `checklist`) after `.pullRequests` in `SidebarSection.workspace.items`, and add the visibility filter in `SidebarView+NativeRows.swift`. Verify with a `SidebarNativeListTests` case: the row is present by default and absent when the toggle is off.
- [x] 5.2 Add `showWorkspaceJira` (default `true`) through `AppSettingsSnapshot`, `CloudSettingsDocument` encode and decode, `AppState` load, apply, and snapshot, and `WorkspaceVisibilityPopover`. Verify with `AppSettingsSnapshotTests` and `CloudSettingsDocumentTests` cases: it round-trips, and a missing field decodes as `true`.
- [x] 5.3 In `MainWindowView`, select `.item(.fileStatus)` when `showWorkspaceJira` turns off while `.item(.jira)` is selected, and return `EmptyView()` for `.item(.jira)` in the main `body` switch. Verify with a build.

## 6. Issue list controller and screen

- [x] 6.1 Add `JiraIssueListController` as described in design §5: generation-guarded loads, cancellation on filter change, 300 ms search debounce, kept rows during refresh, load-more on `nextPageToken`, sprint and project options derived from loaded issues, and the per-repository filter in the `LocalDataStore` collection `jiraIssueFilters`, excluding search text. Verify with `JiraIssueListControllerTests` using a stub client: a stale response is dropped, the filter is restored per repository, search text is not persisted, and a 401 marks the connection as needing reconnection.
- [x] 6.2 Add `JiraIssueListView`:
  - Filter bar with Sprint, Status, Project, Type, search, Reset Filters, and Refresh
  - Flat list rows showing type icon, key, summary, status, priority, and sprint
  - States: loading, "no matching issues", "no issues at all", error with Retry, rate-limited, not connected with "Connect Jira", and needs reconnection
  - Row context menu with Open in Jira, Copy Key, Copy Key and Summary, and Create Branch…
  - Double-click or Return opens the issue in Jira

  Verify with a build.
- [x] 6.3 Wire the screen into `MainWindowView`: a `@StateObject` `JiraIssueListController`, `jiraAccessDecision` and `jiraAccessTaskID` following the Pull Requests versions, a `hasOpenedJira` branch in `cachedRepositoryScreens` that shows the list, `FeatureAccessUnavailableView(feature: .jiraIssues, …)`, or a progress view, and "Connect Jira" opening Settings → Integrations through the existing `onOpenConnections`. Verify with a `FeatureAccessControllerTests` case for `.jiraIssues` and a build. The controller must not load unless access is `.allowed`.

## 7. Create branch from issue

- [x] 7.1 Add `JiraBranchNameSuggester` (key + ASCII slug, at most 60 characters at a hyphen boundary, key always kept). Verify with `JiraBranchNameSuggesterTests`: punctuation, Vietnamese and other diacritics, emoji, an empty summary, and a very long summary.
- [x] 7.2 Add an optional `initialBranchName` to `BranchSheetView` and an optional `initialTopicName` to `StartGitFlowSheet`, both defaulting to `nil`. Thread them through `MainWindowView+Sheets.swift` (`branchSheet`, `startGitFlowSheet`). Verify with a `BranchSheetInitialStateTests` case for the prefilled name, and confirm existing call sites compile unchanged.
- [x] 7.3 Route "Create Branch…" from `JiraIssueListView` to `MainWindowView`: present the Git Flow feature start sheet when Git Flow is configured, otherwise the branch sheet, through the existing sheet presentation state. Verify with a build and with the manual review in 8.2, which checks that undo and refresh work after creation.

## 7a. Issue details panel and branch choices

- [x] 7a.1 Add `JiraBranchTarget` with type-based suggestions (Bug/Defect → bugfix, otherwise feature; plain branch without Git Flow; release excluded). Verify with `JiraBranchNameSuggesterTests` cases for suggestion and options.
- [x] 7a.2 Show `JiraIssueDetailPanel` on single click (key, type, summary, status, priority, project, sprints, updated) with a branch split button plus Open in Jira, Copy Key, and Copy Key and Summary. Make the context menu's Create Branch a submenu of the same choices, and route `prepareCreateBranch(from:target:)` to the matching sheet. Verify with a build, and cover runtime behavior in 8.2.

## 8. Integration validation

- [x] 8.1 Run the new and touched XCTest classes in one invocation and confirm they pass:
  `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/FeatureAccessPolicyTests -only-testing:macgitTests/FeatureAccessNoticeTests -only-testing:macgitTests/FeatureAccessControllerTests -only-testing:macgitTests/JiraSiteNormalizerTests -only-testing:macgitTests/JiraJQLBuilderTests -only-testing:macgitTests/JiraCloudClientTests -only-testing:macgitTests/JiraConnectionStoreTests -only-testing:macgitTests/JiraConnectionControllerTests -only-testing:macgitTests/JiraIssueListControllerTests -only-testing:macgitTests/JiraBranchNameSuggesterTests -only-testing:macgitTests/BranchSheetInitialStateTests -only-testing:macgitTests/SidebarNativeListTests -only-testing:macgitTests/AppSettingsSnapshotTests -only-testing:macgitTests/CloudSettingsDocumentTests test`
- [ ] 8.2 Manual UI review in the running app against a real Jira Cloud site:
  - Connect, reject a bad token, reconnect, and remove in Settings → Integrations
  - The Jira row in Workspace, and hiding it from Customize Workspace
  - The Free/signed-out upgrade view versus the Pro list
  - Default list, each filter, Reset Filters, load-more, and filter memory per repository
  - Error and empty states
  - Open and copy actions
  - Details panel on single click, its actions, and closing it
  - Create Branch in a plain repository, and the suggested and alternative Git Flow choices in a Git Flow repository, followed by undo

  Check the layout at narrow and wide window sizes, and record anything not checked.
- [x] 8.3 Run `git diff --check` and confirm there is no output.

## 9. Cross-repository Firebase contract (`../landing-page`)

- [x] 9.1 In `../landing-page/firestore.rules`, add `showWorkspaceJira` to the `validAppSettings` allowlist with an `is bool` check. Verify by reviewing the diff and running that repository's non-emulator checks. Do not run emulator tests; report them as not run.
- [x] 9.2 Add `jiraIssues` to `featureKeys` in `../landing-page/admin/lib/schemas.ts` (non-scoped) and to `../landing-page/scripts/firebase/set-feature-policy.mjs` as `proOnly` at revision 8. Verify by reviewing the diff and running that repository's type check.
- [ ] 9.3 With explicit user authorization, deploy **Firestore rules only** to the production project before the app release. Verify that the CLI reports success for that project and target, and report what is local, committed, pushed, and deployed.
- [ ] 9.4 With explicit user authorization, publish the release feature policy at revision 8. Verify the published `featurePolicies/release` document contains `jiraIssues`.

## Workflow follow-up

- Archive the change with `/opsx:archive` after implementation, validation, and the Firebase rollout steps are complete.
