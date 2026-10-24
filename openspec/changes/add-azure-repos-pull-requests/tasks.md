# Tasks

## 1. Azure pull request service: read paths

- [x] 1.1 Create `macgit/Services/AzureReposPullRequestService.swift`:
  - A struct conforming to `PullRequestProviding`, with an injected `GitProviderHTTPClient`.
  - URL building for `{hostURL}/{project}/_apis/git/repositories/{repo}`, with percent-encoded segments and `api-version=7.1`.
  - `validate(response:data:)` implementing the error table in design §6.
  - Azure response models.
  - Verify with `AzureReposPullRequestServiceTests` cases for URL encoding (a project with a space) and each error mapping, including a 203 sign-in page.
- [x] 1.2 Implement `listPullRequests` with the status, `$top`/`$skip`, and `hasNextPage` mapping from design §2. Map state, draft, merge readiness, branches without `refs/heads/`, author, and web URL. Verify with tests for the Open, Closed, and All filters, a draft item, and next-page detection.
- [x] 1.3 Override `openPullRequest(sourceBranch:)` to query by `searchCriteria.sourceRefName`. It prefers the active pull request. Verify with tests for an active match, a completed-only match, and no match.
- [x] 1.4 Implement `pullRequestDetail`:
  - Load the pull request and its threads.
  - Skip system and deleted comments.
  - Use the `threadId * 1000 + commentId` IDs.
  - Sort by `publishedDate`.
  - Map file context to `PullRequestReviewContext`.
  - Map reviewers.
  - Verify with a test using a thread fixture that mixes text, system, and deleted comments and includes one file comment.

## 2. Changed files and diffs

- [x] 2.1 Add `GitStatusService.unifiedDiff(original:modified:path:)` to `GitStatusService+Diff.swift`. It uses `git diff --no-index -U3` on temporary files, treats exit 1 as success, rewrites the header paths, and removes the temporary files. Verify with a new `GitStatusServiceUnifiedDiffIntegrationTests` that covers a modified file, an added file (empty original), and identical content (empty diff), and parses the output with `DiffParser`.
- [x] 2.2 Implement `pullRequestChanges`:
  - Take the latest iteration and its changes against `$compareTo=0`.
  - Map statuses, drop folders, and set the previous path for renames.
  - Fetch file contents at `commonRefCommit` and `sourceRefCommit`, four at a time, for the first 100 files.
  - Apply the 1 MB and NUL-byte limits with a `patchUnavailableReason`.
  - Count additions and deletions from the hunks.
  - Verify with tests for a modified file, a rename, a binary file, an oversized file, and the 101st file.

## 3. Write paths

- [x] 3.1 Implement `createComment` (a new active thread) and `createPullRequest` (`refs/heads/` names; a 409 duplicate surfaces Azure's message). Verify the request method, path, and JSON body in `AzureReposPullRequestServiceTests`.
- [x] 3.2 Implement `mergePullRequest`:
  - Send a `PATCH` to `completed` with `noFastForward`, `deleteSourceBranch: false`, and `lastMergeSourceCommit`.
  - Poll up to 10 times, 1 s apart (the delay is injectable in tests).
  - Map the merge failures from design §5.
  - Verify with tests for immediate completion, queued then completed, `rejectedByPolicy`, a 400 policy message, and a timeout.

## 4. Visibility, registration, and UI

- [x] 4.1 Add `AzureReposRepositoryVisibilityService: RepositoryVisibilityProviding`, which reads `project.visibility` from the repository API. Anonymous rejection maps to `authorizationRequired`. Register it as `.azureDevOps` in `macgitApp.swift`. Verify with `AzureReposRepositoryVisibilityServiceTests` (public, private with a token, anonymous rejection) and an Azure case in `RepositoryVisibilityControllerTests`.
- [x] 4.2 Register `.azureDevOps: AzureReposPullRequestService()` in the `PullRequestController` services in `MainWindowView.swift`. Add `PullRequestControllerTests` cases showing that an Azure remote with a connected PAT account loads a list, and that an SSH Azure account with a kept token is used.
- [x] 4.3 Hide the Reviewers and Assignees pickers in `CreatePullRequestSheet` for Azure Repos, and skip `loadCreateDraftParticipants` for Azure. Verify with a `PullRequestControllerTests` case showing that no participant request is made for Azure, and with a build.
- [x] 4.4 When pull request detail has no cache, show the window's "Opening Pull Request #N..." progress overlay until the detail loads, then open the detail window. Cached detail opens at once and refreshes in the background. This applies to every provider. Verify with `PullRequestControllerTests.testHasCachedPullRequestDetailReflectsDiskCache` and a build.

## 5. Validation

- [x] 5.1 Run the following, one after another:

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' \
    -only-testing:macgitTests/AzureReposPullRequestServiceTests \
    -only-testing:macgitTests/AzureReposRepositoryVisibilityServiceTests \
    -only-testing:macgitTests/GitStatusServiceUnifiedDiffIntegrationTests \
    -only-testing:macgitTests/PullRequestControllerTests \
    -only-testing:macgitTests/RepositoryVisibilityControllerTests \
    -only-testing:macgitTests/GitLabPullRequestServiceTests \
    -only-testing:macgitTests/GitHubPullRequestServiceTests test
  ```

  Then run `git diff --check`.
- [x] 5.2 Manual UI review with the `Trantienthanh1998/ChatApp` Azure repository and a Code (Read & Write) PAT:
  - Open Pull Requests and switch the Open, Closed, and All filters.
  - Open a pull request and check its conversation and Changes diffs.
  - Add a comment.
  - Create a pull request from the sheet, and check that it has no participant pickers.
  - Merge a test pull request.
  - Check the sidebar's branch pull request action.
  - Report anything that was not checked.
