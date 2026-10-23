# Proposal

## Why

Commit+ connects GitHub, GitLab, and Bitbucket accounts, but teams on Azure DevOps cannot use Azure Repos remotes with stored credentials, provider links, bookmarks, or repository browsing. Azure remotes such as `https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp` are not recognized at all today because every resolver assumes an `owner/repo` path.

## What Changes

- Add Azure Repos (Azure DevOps Services on `dev.azure.com`) as a fourth Git provider kind, shown as "Azure Repos" in Settings → Connections and the repository picker.
- Recognize Azure remote URLs in all current forms: `https://[user@]dev.azure.com/{org}/{project}/_git/{repo}`, legacy `https://{org}.visualstudio.com[/DefaultCollection]/{project}/_git/{repo}`, `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}`, and legacy `{org}@vs-ssh.visualstudio.com:v3/{org}/{project}/{repo}`, including percent-encoded names with spaces. All forms of one repository resolve to the same identity.
- Connect an Azure account per organization with a personal access token (HTTPS) validated against Azure DevOps, or with an SSH key. The account supplies credentials for fetch, pull, push, and clone of that organization's repositories.
- Open Azure pages from the app: repository web page, pull request list, and "Create Pull Request" in the browser (`.../_git/{repo}/pullrequestcreate?sourceRef=...`). Azure has no repository issues page, so no issues link is offered.
- Recognize Azure remotes as repository bookmarks with a dedicated provider and filter them in the repository picker.
- Browse an Azure account's repositories (across all projects of the organization) in the existing repository browser to clone them.
- Update Firestore rules in `../landing-page` so synced provider accounts and bookmarks accept the new provider value. This is a cross-repository rollout blocker: the rules must be deployed before an app build that writes Azure documents ships.

Out of scope: in-app pull request list/create/review, merged-branch detection, branch protection, Microsoft Entra ID OAuth sign-in, and Azure DevOps Server (on-premises).

## Capabilities

### New Capabilities
- `azure-repos-account-connection`: connecting, editing, reconnecting, and disconnecting an Azure DevOps organization account with a PAT or SSH key, using it for Git credentials, and browsing its repositories.
- `azure-repos-remote-recognition`: recognizing Azure Repos remote URLs as one repository identity and using that identity for provider links, browser pull request creation, bookmarks, and repository picker filtering.

### Modified Capabilities

None. No existing spec in `openspec/specs/` covers Git provider accounts.

## Impact

- Models: `GitProviderKind`, `GitProviderHost`, `RepositoryBookmarkProvider`, `GitRepositoryIdentity.browserURL`, `RepositoryBookmarkRemote`.
- Services: `GitRemoteIdentityResolver`, `GitProviderCredentialResolver`, `GitProviderSSHAuthService`, `GitProviderRepositoryDiscoveryService`, `PullRequestURLBuilder`, `BranchProtectionService` and `BranchMergeDetectionController` (explicit unsupported branches), a new `AzureDevOpsProviderAuthService` for PAT validation.
- App/UI: `GitProviderAccountController`, `GitProviderAddAccountSheet`, `GitProviderAccountsPresentationPolicy`, `GitProviderAccountRow`, `GitProviderAccountsSection`, `GitProviderRepositoryBrowser`, `RepoPickerView`, `MainWindowView+PullRequestActions` (error text).
- Firebase (`../landing-page`): `firestore.rules` provider allowlists for `gitProviderAccounts` and repository bookmarks; rules deployment required.
- Compatibility: older app versions fail to decode the whole synced account (and bookmark) list when one document has an unknown provider, so cloud sync of provider accounts and bookmarks stops on Macs that have not updated until they upgrade. Local data is not deleted (see design).
- No new dependencies. No plan-gating change: Azure accounts count toward the existing provider-account limit like other providers.
