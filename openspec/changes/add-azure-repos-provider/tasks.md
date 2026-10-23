# Tasks

## 1. Provider model and Azure remote parsing

- [x] 1.1 Add `GitProviderKind.azureDevOps` (raw `"azure"`, display "Azure Repos") and update every exhaustive switch on it (`GitProviderHost.isSelfHosted`/`apiURL`, `GitRepositoryIdentity.browserURL`, `GitProviderSSHAuthService.username`, `GitProviderAccountsPresentationPolicy.host(for:)`, `GitProviderAccountController` OAuth/PAT/reconnect switches, `BranchProtectionService` → `.unsupported`); verify with an app build and `GitProviderAccountModelsTests` cases for `isSelfHosted == false` and Codable round-trip of `"azure"`.
- [x] 1.2 Add `Services/AzureReposRemote.swift` that parses the four remote forms plus organization-only input and builds the percent-encoded canonical URL; verify with a new `AzureReposRemoteTests` covering `https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp`, the SSH `v3` form, `visualstudio.com` with and without `DefaultCollection`, `vs-ssh`, `%20` names, missing `_git`, and invalid organization input.
- [x] 1.3 Route `GitRemoteIdentityResolver.identity` through the Azure parser before the known-hosts branch, producing a lowercased-organization `hostURL`, `ownerPath = project`, and the canonical URL; verify in `GitRemoteIdentityResolverTests` that all forms of one repository yield equal identities and equal `GitProviderAccountPreferenceKey` values, and that existing GitHub/GitLab/Bitbucket cases still pass.

## 2. Links, pull request URL, bookmarks, and picker

- [x] 2.1 Add the Azure case to `PullRequestURLBuilder` (`pullrequestcreate?sourceRef=` with `/` encoded) and update the "not a recognized pull request host" messages in `MainWindowView+PullRequestActions` to include Azure Repos; verify with `PullRequestURLBuilderTests` for HTTPS, SSH, and legacy remotes and `feature/login`.
- [x] 2.2 Make `MainWindowView.browserURL(from:)` and `GitRepositoryIdentity.browserURL` return the canonical Azure web URL for SSH and HTTPS remotes; verify with a unit test on the URL helper (add one to `PullRequestURLBuilderTests` or a new focused test if the helper is extracted).
- [x] 2.3 Add `RepositoryBookmarkProvider.azureDevOps` (raw `"azure"`), resolve Azure remotes in `RepositoryBookmarkIdentity.resolve` (`ownerPath = "{org}/{project}"`, canonical remote URL and key), and set `RepositoryBookmarkRemote.pullRequestsURL` to `{canonical}/pullrequests` and `issuesURL` to nil; verify in `RepositoryBookmarkTests` that HTTPS/SSH/legacy forms produce the same canonical key and document ID.
- [x] 2.4 Decode synced accounts and bookmarks per document, skipping unknown providers instead of failing the fetch (`FirestoreGitProviderAccountStore.accounts`, `FirestoreRepositoryBookmarkStore.bookmarks`); verify in `GitProviderAccountStoreTests` and `RepositoryBookmarkTests` with a document whose provider is `"unknown"`.
- [x] 2.5 Add the `azure` image asset, the `RepoPickerFilterType.azureDevOps` filter, and Azure detection in `determineRepoIconName`; verify in `RepoPickerViewTests` that Azure remotes map to the new icon and filter.

## 3. Account connection (PAT and SSH)

- [x] 3.1 Add `AzureDevOpsProviderAuthService` that validates a PAT via `_apis/connectionData` (Basic auth, `X-TFS-FedAuthRedirect: Suppress`, 401/203/non-JSON → rejected) and builds a `GitProviderAccount`; verify with a new `AzureDevOpsProviderAuthServiceTests` using a stubbed HTTP client for success, 401, 203 HTML, and a missing `Account` property fallback.
- [x] 3.2 Add `GitProviderAccountController.connectAzureDevOps(organizationInput:accessToken:replacing:)` through `saveAuthorizedAccount`, plus Azure handling in `reconnect`; verify in `GitProviderAccountControllerTests` for a new account, a duplicate org+user, a replaced token for the same user, a different-user replacement rejected, and the free-plan account limit.
- [x] 3.3 Support Azure SSH in `GitProviderSSHAuthService` (`git@ssh.dev.azure.com`, success on "Shell access is not supported") and pass the organization as the `connectSSH` username override; verify in `SelfHostedGitProviderTests` (or the existing SSH auth test location) that the output parser accepts the Azure success text and rejects "Permission denied".
- [x] 3.4 Verify credential routing through the controller's `credentialResolver()` in `GitProviderAccountControllerTests`: an HTTPS account for `trantienthanh1998` supplies the PAT for the embedded-username, plain, and `visualstudio.com` remotes; an SSH account supplies its key for `git@ssh.dev.azure.com:v3/…`; a different organization gets no credential.

## 4. Add-account UI and repository browsing

- [x] 4.1 Add the Azure Repos host option, Organization field, PAT field with scope hint, "Get Personal Access Token" link, and account row/section text (`GitProviderAccountsPresentationPolicy`, `GitProviderAddAccountSheet`, `GitProviderAccountRow`, `GitProviderAccountsSection`); verify in `GitProviderAccountsSectionTests` for host options, disabled OAuth, `canConnect`, and `initialAuthType` for Azure accounts.
- [x] 4.2 Add the Azure branch to `GitProviderRepositoryDiscoveryService.repositories` (`_apis/git/repositories?api-version=7.1`, Basic auth, drop disabled repositories, `{project}/{repo}` names, userinfo-stripped HTTPS or `sshUrl` clone URL, single page) and allow Azure accounts in `GitProviderRepositoryBrowser`; verify with a new `GitProviderRepositoryDiscoveryServiceTests` using a stubbed HTTP client for listing, disabled filtering, SSH URLs, and 401.
- [ ] 4.3 Manual UI review: launch the app, add an Azure Repos account for organization `Trantienthanh1998` with a PAT, browse and clone `ChatApp/ChatApp`, fetch and push, open the remote and "Create Pull Request" in the browser, bookmark the repository, and use the Azure Repos picker filter; check the add-account sheet layout for both HTTPS and SSH at the default Settings size. Report anything not checked.

## 5. Firebase rules (../landing-page)

- [x] 5.1 In `../landing-page/firestore.rules`, add `'azure'` to the `provider` allowlists of the Git provider account and repository bookmark validators, and add Azure cases next to the Bitbucket ones in `firebase-tests/firestore.rules.test.mjs`; verify by reviewing the diff (emulator tests not run).
- [x] 5.2 Deploy Firestore rules only (no Functions, indexes, or other targets) to the production project after explicit user authorization; verify the CLI deploy result for the intended project and report local/committed/deployed state separately.

## 6. Validation

- [x] 6.1 Run the XCTest classes touched above sequentially in one invocation: `-only-testing:macgitTests/AzureReposRemoteTests -only-testing:macgitTests/GitRemoteIdentityResolverTests -only-testing:macgitTests/PullRequestURLBuilderTests -only-testing:macgitTests/RepositoryBookmarkTests -only-testing:macgitTests/GitProviderAccountModelsTests -only-testing:macgitTests/GitProviderAccountStoreTests -only-testing:macgitTests/GitProviderAccountControllerTests -only-testing:macgitTests/GitProviderCredentialResolverTests -only-testing:macgitTests/GitProviderAccountsSectionTests -only-testing:macgitTests/AzureDevOpsProviderAuthServiceTests -only-testing:macgitTests/GitProviderRepositoryDiscoveryServiceTests -only-testing:macgitTests/SelfHostedGitProviderTests -only-testing:macgitTests/RepoPickerViewTests -only-testing:macgitTests/BranchProtectionServiceTests`; all pass.
- [x] 6.2 Run `git diff --check` in both repositories and `openspec validate add-azure-repos-provider --strict`; both clean.
