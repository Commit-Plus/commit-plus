# Proposal

## Why

Azure Repos accounts can now be connected, but pull requests for Azure remotes only open in the browser. The in-app Pull Requests view reports that the provider is not supported. Users who connect Azure Repos expect the same in-app pull request workflow as GitHub and GitLab: list, open, read the conversation, view the changed files, comment, merge, and create.

There is a second, quieter gap. Pull request access is gated by repository visibility, and Azure Repos has no visibility lookup, so every Azure repository resolves to "unknown". That makes the pull request gate deny access even for Pro users, including the browser "Create Pull Request" action. Git Flow and Git LFS are gated the same way.

## What Changes

- Add an Azure Repos pull request service. It uses the connected account's personal access token against the Azure DevOps Git REST API (api-version 7.1) and supports:
  - Listing pull requests with the Open, Closed, and All filters, the "Created by me" filter, and paging. Each pull request shows its state (active, draft, completed, or abandoned), its source and target branches, and whether it is ready to merge.
  - Finding the open pull request for a branch, used by the sidebar and branch actions.
  - Pull request detail, with the description, reviewers, and the text comment threads. System threads are excluded, and file comments keep their file path and line.
  - Changed files with a viewable unified diff for each text file, within stated size limits.
  - Adding a comment as a new thread.
  - Merging by completing the pull request with a merge commit, without deleting the source branch.
  - Creating a pull request from the existing create sheet. Azure Repos has no assignees, and its reviewer directory needs a broader token scope, so this sheet hides the Reviewers and Assignees pickers for Azure.
- Add an Azure Repos repository visibility service, so the existing plan gating classifies Azure repositories as public or private instead of unknown. Free users get pull requests for public Azure projects, and Pro users get them for all Azure projects, as for GitHub and GitLab. Git Flow and Git LFS gating benefit from the same fix.
- Map Azure errors to the existing pull request error messages:
  - A rejected or expired token asks the user to reconnect.
  - A missing permission names the "Code (Read & Write)" scope.
  - Branch policies that block a merge show Azure's message.
- Register both services where the GitHub and GitLab services are registered.

Out of scope:
- Checking out a pull request through `refs/pull/{id}`. Azure only publishes a merge ref there, so checkout keeps the existing source-branch behavior used for GitLab.
- Reviewer and assignee selection when creating a pull request.
- Votes and approvals.
- Resolving threads.
- Merge strategies other than a merge commit, and auto-complete.
- Merged-branch detection, branch protection, and notifications for Azure Repos.
- Azure DevOps Server (on-premises).

## Capabilities

### New Capabilities
- `azure-repos-pull-requests`: in-app pull request list, detail, changed files, comment, merge, and creation for Azure Repos remotes, plus Azure repository visibility for plan gating.

### Modified Capabilities
- `azure-repos-remote-recognition`: the requirement "Pull requests are created in the browser for Azure Repos" no longer says that in-app pull request listing and creation report the provider as unsupported. Browser creation stays as it is.

## Impact

- New `macgit/Services/AzureReposPullRequestService.swift` (conforms to `PullRequestProviding`) and `AzureReposRepositoryVisibilityService` (conforms to `RepositoryVisibilityProviding`). Both reuse the request helpers in `AzureDevOpsProviderAuthService`.
- A new `GitStatusService` diff helper that builds a unified diff from two file contents. Azure does not return patches.
- Registration of the new services:
  - `MainWindowView.swift`: the services dictionary of `PullRequestController`.
  - `macgitApp.swift`: the services of `RepositoryVisibilityController`.
- `CreatePullRequestSheet` hides the participant pickers for Azure Repos.
- New `AzureReposPullRequestServiceTests` and `AzureReposRepositoryVisibilityServiceTests`, plus Azure cases in `PullRequestControllerTests`.
- No Firebase contract, synced settings, or feature-policy change. The `pullRequests` feature key and its local fallback are unchanged.
