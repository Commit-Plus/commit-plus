# Design

## Context

Provider support is spread over several switches on `GitProviderKind` (`GitProviderAccountModels.swift`) and a few places that sniff host strings on their own (`RepositoryBookmarkIdentity.provider(for:)`, `PullRequestURLBuilder.hostProvider`, `determineRepoIconName`, `MainWindowView.browserURL(from:)`). Every parser assumes `{owner…}/{repo}` paths: `GitRemoteIdentityResolver` only allows nested owners for GitLab, and `RepositoryBookmarkIdentity.resolve` joins all but the last component into the owner path. An Azure path such as `/{org}/{project}/_git/{repo}` therefore either fails or yields `ownerPath = "{org}/{project}/_git"`.

Bitbucket is the closest precedent: token-only HTTPS (`connectBitbucket`, token type `Basic`), no OAuth, no discovery, no PR service. Azure follows that model for auth but adds discovery.

Account matching (`GitProviderCredentialResolver.matchingAccounts`) compares `provider` and `GitProviderHost.identityKey(hostURL)`, which lowercases the host but keeps the path. `GitProviderAccountPreferenceKey` uses the same key plus `ownerPath`/`repositoryName`.

Cloud sync: `FirestoreGitProviderAccountStore.accounts` and `FirestoreRepositoryBookmarkStore.bookmarks` decode every document with `try`, so one unknown `provider` value fails the whole fetch. `LocalGitProviderAccountStore.updateCloudAccount` swallows that error and skips the sync.

## Goals / Non-Goals

**Goals:**
- One place that parses Azure remotes, reused by every resolver that currently sniffs hosts.
- Keep the existing account, credential, preference, and sync flows; Azure plugs in as another `GitProviderKind`.

**Non-Goals:**
- A `PullRequestProviding` implementation, merge detection adapter, or branch protection lookup for Azure (explicit `.unsupported` paths only).
- Refactoring the other providers' host sniffing beyond adding the Azure branch.

## Decisions

### 1. Provider kind and host model
Add `GitProviderKind.azureDevOps` with raw value `"azure"` (the stored Firestore and SQLite value) and display name "Azure Repos". An account's `hostURL` is `https://dev.azure.com/{org}` with the organization **lowercased**, so the existing `identityKey` comparison is case-insensitive for organizations without special-casing it. `GitProviderHost.isSelfHosted` returns `false` for Azure (no Pro gate for self-managed servers); `apiURL` returns the organization URL. `GitProviderHost.configured` keeps rejecting Azure; organization input goes through the parser in decision 2.

*Alternative:* one account per Microsoft identity covering all organizations. Rejected: a PAT is usually scoped to one organization, the existing model has one `hostURL` per account, and matching by organization fits `matchingAccounts` unchanged.

### 2. A dedicated Azure remote parser
Add `AzureReposRemote` (new file in `Services/`) that parses all four remote forms from the spec and organization-only inputs (`org`, `https://dev.azure.com/org[/…]`, `org.visualstudio.com`). It returns `organization` (original case), `project`, `repository` (percent-decoded), and builds the canonical `https://dev.azure.com/{org}/{project}/_git/{repo}` with percent-encoding. Hosts handled: `dev.azure.com`, `ssh.dev.azure.com` (path `v3/…`), `*.visualstudio.com`, `vs-ssh.visualstudio.com`. `DefaultCollection` is skipped only in the legacy `visualstudio.com` form.

Callers:
- `GitRemoteIdentityResolver.identity` checks the Azure parser first (before the known-hosts branch, whose `parts.count == 2` rule would reject Azure). It returns `GitRemoteIdentity(provider: .azureDevOps, hostURL: https://dev.azure.com/{org lowercased}, ownerPath: project, repositoryName: repo, canonicalHTTPSURL: canonical)`.
- `RepositoryBookmarkIdentity.resolve` uses it to produce `RepositoryBookmarkProvider.azureDevOps` (raw value `"azure"`), host `dev.azure.com`, `ownerPath = "{org}/{project}"`, canonical remote URL, and canonical key `dev.azure.com/{org}/{project}/{repo}` lowercased.
- `PullRequestURLBuilder.build`/`canBuild` check the Azure parser first and build `{canonical}/pullrequestcreate?sourceRef={branch}` (branch encoded with `.alphanumerics` plus `-._~`, so `/` becomes `%2F`).
- `MainWindowView.browserURL(from:)`, `RepositoryBookmarkRemote.webURL` and `pullRequestsURL` (`{canonical}/pullrequests`, `issuesURL = nil`), `GitRepositoryIdentity.browserURL`, and `determineRepoIconName` use the canonical URL or parser result.

Web and PR URLs keep the organization's original case from the remote; only matching keys are lowercased.

*Alternative:* extend the generic path splitting with an `_git` special case in each resolver. Rejected: four copies of the same tricky parsing (SSH `v3`, legacy hosts, `DefaultCollection`, percent-encoding).

### 3. PAT validation through `connectionData`
New `AzureDevOpsProviderAuthService` (mirrors `GitLabProviderAuthService.fetchAccount`) calls `GET https://dev.azure.com/{org}/_apis/connectionData` with `Authorization: Basic base64(":" + PAT)` and `X-TFS-FedAuthRedirect: Suppress` (so a bad token returns 401 rather than a 203/302 sign-in page). A non-2xx status, a 203, or a non-JSON body is treated as a rejected token. From `authenticatedUser` it reads `id` → `providerUserID`, `providerDisplayName` → `displayName`, and `properties.Account.$value` (email) → `username`, falling back to the display name.

`connectionData` works with any PAT scope, unlike the profile API, which needs `vso.profile`. Missing Code scope surfaces later as a Git 401 or a discovery error.

`GitProviderAccountController.connectAzureDevOps(organizationInput:accessToken:replacing:)` follows `connectPersonalAccessToken`: it runs `authorizeConnection`/`authorizeNewAccountCreation`, sets `permissions["authentication"] = "personalAccessToken"`, keeps `scopes = []`, stores token type `"Basic"`, and saves through `saveAuthorizedAccount` so the existing duplicate and different-account checks apply. `reconnect` for Azure sets an error asking for a new token, like Bitbucket.

The Git credential is `GitCredential(username: account.username, token: PAT)`. Azure ignores the username for PAT auth, and when the remote embeds `org@` Git only asks the askpass helper for the password. The askpass host check compares the authority without userinfo (`${authority##*@}`), so `org@dev.azure.com` already matches.

### 4. SSH
`GitProviderSSHAuthService` maps Azure to `git@ssh.dev.azure.com` and treats output containing `Shell access is not supported` as success. Azure does not return a user name, so the account username is the organization name, and `connectSSH` receives it through the existing `usernameOverride` (as Bitbucket does). The account's `hostURL` is the organization URL from decision 1, so `sshCredential` matching works unchanged. `sshUsername(from:)` already yields `git` for `git@ssh.dev.azure.com:` and `{org}` for `vs-ssh` remotes.

### 5. Repository discovery
`GitProviderRepositoryDiscoveryService.repositories` gets an Azure branch: `GET https://dev.azure.com/{org}/_apis/git/repositories?api-version=7.1` with Basic auth, decoding `value[]` (`name`, `project.name`, `remoteUrl`, `sshUrl`, `isDisabled`). Disabled repositories are dropped; names are `"{project}/{name}"`. HTTPS clone URLs are `remoteUrl` with userinfo stripped (keeps Azure's casing); SSH uses `sshUrl`. The endpoint returns all repositories at once, so `page > 1` returns an empty page and `hasNextPage` is `false`. A 401/203 response maps to the existing "invalid or expired" message. `GitProviderRepositoryBrowser` stops excluding the provider for Azure (it still excludes Bitbucket).

### 6. Add-account UI
`GitProviderAddAccountHost.azureDevOps` ("Azure Repos") is added to `hostOptions`. Auth options are `[OAuth disabled, "Personal Access Token"]`, so the auth picker hides as it does for Bitbucket. The sheet shows an "Organization" field for both protocols, a PAT `SecureField` with the hint "Requires Code (Read & Write) scope.", and a "Get Personal Access Token" button that opens `https://dev.azure.com/{org}/_usersSettings/tokens` (or `https://aex.dev.azure.com/` when the organization is empty). The self-hosted toggle is hidden. `GitProviderAccountRow` shows "HTTPS (Personal Access Token)" and the organization. The account-section explanatory text mentions Azure Repos. The sheet lives in a Settings window; no menu, toolbar, or window-scoped notification is added.

`RepoPickerFilterType.azureDevOps` ("Azure Repos") uses a new `azure` image asset in `Resources/Assets.xcassets` (named after the provider raw value, which `GitProviderAccountRow` uses as its asset name), matching the existing 512px PNG provider icons.

### 7. Unsupported features stay explicit
`BranchProtectionService` returns `.unsupported` for Azure. `BranchMergeDetectionController` already falls back when `services[provider]` is nil; its message stays. `PullRequestController` has no Azure service, so its existing `unsupportedProvider` path covers the in-app windows. The PR error strings in `MainWindowView+PullRequestActions` list Azure Repos.

### 8. Forward-compatible decoding
New builds decode synced accounts and bookmarks per document and skip documents whose `provider` is unknown, instead of failing the whole fetch. This does not help already-shipped versions (see Risks) but stops the next provider addition from repeating the problem.

### 9. Firebase rules (cross-repository)
In `../landing-page/firestore.rules`, add `'azure'` to the `provider` allowlist in `validGitProviderAccount` and `validRepositoryBookmark`. Add rule tests in `firebase-tests/firestore.rules.test.mjs` next to the Bitbucket cases (an Azure account document and an Azure bookmark with `ownerPath` `org/project`). Emulator tests are not run in this workflow. Only the Firestore rules target needs deploying; no Functions, indexes, or feature-policy changes.

## Risks / Trade-offs

- [Older app versions fail the entire account/bookmark cloud fetch when an `azure` document exists] → Sync on those Macs stops but local data is kept. Release notes should recommend updating every Mac; decision 8 prevents a repeat.
- [Rules not deployed before the app ships] → Every save of an Azure account or bookmark to Firestore is rejected. Deploy rules first (migration step 1).
- [`connectionData` is not a formally documented public API] → It is the endpoint Azure DevOps clients use for identity and has been stable. If it changes, fall back to `_apis/projects?$top=1` for validation and use the organization as username.
- [Lowercased organization in `hostURL`] → Account rows display the organization in lowercase. Accepted; the original case is shown where it comes from remotes or discovery.
- [PATs with an "All accessible organizations" scope still create one account per organization] → Matches the per-organization model; users add another account for another organization.
- [Microsoft is restricting PAT creation and lifetime in some tenants] → Entra ID OAuth remains a follow-up; this change does not block it.

## Migration Plan

1. In `../landing-page`: update `firestore.rules` and the rules tests, review the diff, then deploy **Firestore rules only** to the production project after explicit user authorization. Verify the CLI deploy result.
2. Ship the app build with Azure support. Rollback: revert the app change; the rules change is additive and can stay deployed.

## Open Questions

- Which SSH key types Azure DevOps currently accepts (historically RSA only). The app does not restrict key types; the SSH test surfaces Azure's error, so this only affects the help text.
