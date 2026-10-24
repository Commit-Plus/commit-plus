# Design

## Context

In-app pull requests already run through a single path:
- **Controller:** `PullRequestController`, created per repository window in `MainWindowView`.
- **Service lookup:** a `[GitProviderKind: any PullRequestProviding]` dictionary. Today it holds only `.github` and `.gitlab`. Any other provider falls through to `PullRequestProviderError.unsupportedProvider`.
- **Repository identity:** `GitRemoteIdentityResolver` already turns an Azure remote into a `GitRepositoryIdentity` with:
  - `provider: .azureDevOps`
  - `hostURL: https://dev.azure.com/{org lowercased}`
  - `owner: {project}`
  - `name: {repo}`
- **Account matching and tokens:** `matchingAccounts` and `apiCredential` already match Azure accounts by organization URL. They accept them because Azure accounts carry `permissions["authentication"] == "personalAccessToken"`.
- **Web URL:** `GitRepositoryIdentity.browserURL` already builds the Azure web URL.

So the controller, cache, views, and account resolution need no structural change. What is missing is the Azure service.

Plan gating goes through `RepositoryVisibilityController.accessDecision`. It has no visibility service for `.azureDevOps`, so it returns `.unknown`, and `FeatureAccessResolver` denies scoped features (`pullRequests`, `gitFlow`, `gitLFS`) on `.unknown` for every plan.

The Azure DevOps REST API differs from the GitHub and GitLab APIs in ways that shape the design:
- Pull requests are listed with `$top`/`$skip`, with no page headers.
- Status is one of `active`, `completed`, `abandoned`, or `all`.
- Comments live in threads, with comment IDs that are unique only within a thread.
- No unified patch is returned for changed files.
- Completing a pull request is a `PATCH` that can finish asynchronously.

The existing request helpers handle Azure authentication: `AzureDevOpsProviderAuthService.apiRequest` sets Basic auth with an empty user name and `X-TFS-FedAuthRedirect: Suppress`, and `isRejected` detects 401, 203, redirects, and non-JSON sign-in pages.

## Goals / Non-Goals

**Goals:**
- Give Azure Repos the same in-app pull request features as GitHub and GitLab:
  - list, filters, and paging
  - branch lookup
  - detail and conversation
  - changed files with diffs
  - comment
  - merge
  - create
- Resolve Azure repository visibility so plan gating behaves as it does for the other providers.
- Keep tokens out of logs, errors, and Repository AI context.

**Non-Goals:**
- Fetching `refs/pull/{id}/merge` for checkout.
- Reviewer and assignee pickers.
- Votes and approvals.
- Thread resolution.
- Squash, rebase, or semi-linear merges.
- Auto-complete.
- Merged-branch detection, branch protection, and notifications.
- Azure DevOps Server.

## Decisions

### 1. `AzureReposPullRequestService: PullRequestProviding`, registered next to GitHub and GitLab

- **Location:** a new `macgit/Services/AzureReposPullRequestService.swift`.
- **Structure:** it follows `GitLabPullRequestService`. It is a struct with an injected `GitProviderHTTPClient`, so tests use the existing fake client.
- **Requests:** it builds requests with `AzureDevOpsProviderAuthService.apiRequest(url:token:)`, adding `Content-Type: application/json` and the method for writes.
- **Base URL:** `{hostURL}/{project}/_apis/git/repositories/{repo}`. Every query includes `api-version=7.1`. Project and repository names are percent-encoded as path segments.
- **Ownership:**
  - `PullRequestController` keeps owning state, caching, comment refresh, and post-merge invalidation.
  - `MainWindowView` adds `.azureDevOps: AzureReposPullRequestService()` to the services dictionary.
  - No new controller.
- **Window scoping:** unchanged. Each window owns its `PullRequestController`, and no new menu, toolbar, or notification commands are added.

### 2. API mapping

| Feature | Azure call | Notes |
|---|---|---|
| List | `GET pullrequests?searchCriteria.status={active\|all}&$top={perPage+1}&$skip={(page-1)*perPage}` | Open filter → `active`. Closed and All filters → `all`. `PullRequestController.visibleItems` already removes items that do not match the filter, so a Closed page can show fewer than 30 rows (see Risks). The extra item sets `hasNextPage`. Azure returns the newest first. |
| Branch lookup | `GET pullrequests?searchCriteria.sourceRefName=refs/heads/{branch}&searchCriteria.status=all&$top=50` | Overrides the default implementation, which scans every page. Picks the active pull request, else the first. |
| Detail | `GET pullrequests/{id}` + `GET pullrequests/{id}/threads` | Reviewers come from `reviewers[].displayName`. Assignees are `[]`. |
| Changes | `GET pullrequests/{id}/iterations` (last) → `GET pullrequests/{id}/iterations/{n}/changes?$compareTo=0&$top=2000` | Content comes from `GET items?path=…&versionDescriptor.versionType=commit&versionDescriptor.version={sha}&$format=octetStream`. |
| Comment | `POST pullrequests/{id}/threads` | Body: `{comments:[{parentCommentId:0,content,commentType:1}],status:1}`. |
| Merge | `PATCH pullrequests/{id}` | Body: `{status:"completed",lastMergeSourceCommit:{commitId},completionOptions:{mergeStrategy:"noFastForward",deleteSourceBranch:false}}`. |
| Create | `POST pullrequests` | Body: `{sourceRefName,targetRefName,title,description}`. |
| Participants | none (protocol default `[]`) | |

How Azure fields map to the summary:
- **`state`:** `active` → `.open`, or `.draft` when `isDraft`. `completed` → `.merged`. `abandoned` → `.closed`.
- **`mergeReadiness`:** `mergeStatus` `succeeded` → `.ready`. `conflicts`, `rejectedByPolicy`, and `failure` → `.blocked`. Anything else → `.unknown`.
- **`checkState`:** stays `.unknown`, because the policy-evaluation API needs a broader scope.
- **Branches:** `source`/`target` are taken from `sourceRefName`/`targetRefName` without `refs/heads/`, and `sha` from `lastMergeSourceCommit`/`lastMergeTargetCommit`.
- **`author`:** `createdBy.uniqueName` (falling back to `displayName`) is used as `username`, so "Created by me" compares with the account's `username`, which is the same Azure account name. Avatars stay `nil`: Azure avatar URLs need authentication and `PullRequestAuthorAvatar` loads them anonymously, so the existing initials fallback is shown.
- **`webURL`:** `{canonical}/pullrequest/{id}`.

### 3. Threads become `PullRequestComment`s

- **Which comments:** only threads that are not deleted, and within them only comments where `commentType == "text"` and `isDeleted != true`. Azure's own comments have `commentType == "system"` (votes, pushes, policy updates) and are skipped.
- **ID:** Azure comment IDs are unique only per thread, so `id = threadId * 1000 + commentId`. A thread with more than 999 comments would collide; this is accepted as unrealistic.
- **Order:** comments are sorted by `publishedDate`.
- **File comments:** `threadContext.filePath` (without the leading `/`) and `rightFileStart.line`, or `leftFileStart.line` with side `LEFT`, become a `PullRequestReviewContext` with `diffHunk: nil`.
- **`webURL`:** the pull request URL with `?discussionId={threadId}`.

### 4. Diffs are built locally from file contents

Azure returns no patch. The service fetches both versions of each changed text file and asks a new `GitStatusService` helper to diff them.

Rejected alternatives:
- **Local git on the user's repository.** It needs the iteration commits to be present, which would mean fetching `refs/pull/{id}/merge` into the user's repository. That has the side effect of a new ref, and the commits may be missing.
- **Azure's `filediffs` endpoint.** It returns line ranges, not text.

How the diff is built:
- **Commits:** the latest iteration's `commonRefCommit` (base) and `sourceRefCommit` (head), which matches what the Azure web UI shows by default.
- **Paths:** the original path is `originalPath` for renames, otherwise `item.path`.
- **Status:** `changeType` contains `add`, `delete`, `rename`, or `edit` and maps to `.added`, `.deleted`, `.renamed`, or `.modified`. Folder entries (`isFolder`) are dropped.
- **Limits:** patches are built for at most the first 100 files, four at a time.
  - A version larger than 1 MB, or containing a NUL byte in its first 8 KB, gets `patch: nil` and a `patchUnavailableReason` naming the cause and saying the diff is available on Azure DevOps.
  - Added and deleted files diff against empty content.
- **Helper:** a new `GitStatusService.unifiedDiff(original:modified:path:)` in `GitStatusService+Diff.swift`.
  - It writes both contents to a private temporary directory and runs `git diff --no-index --no-color -U3` through the existing `runGitRaw`. Exit status 1 means "differences", not failure.
  - It rewrites the `a/`/`b/` header paths to the repository path, so `DiffParser` and the file list agree.
  - It removes the temporary files afterward.
  - The helper does not touch any repository.
- **Additions and deletions:** counted from the parsed hunks.

The result is cached by the existing changes cache (TTL 300 s), so diffs are not rebuilt on every view.

### 5. Merge waits for completion

A `PATCH` to `completed` can return while `status` is still `active` and `mergeStatus` is `queued`. After the `PATCH`, the service polls `GET pullrequests/{id}` up to 10 times, 1 second apart:
- **`completed`:** success.
- **`mergeStatus` is `conflicts`, `rejectedByPolicy`, or `failure`:** throw `providerMessage` with `mergeFailureMessage`, or a default message.
- **Still active after 10 attempts:** throw "Azure DevOps is still completing the pull request. Refresh to see the result."

A policy that blocks the `PATCH` itself returns 400 or 409 with a `message`, which is shown as is. `PullRequestController` already invalidates the list and detail caches after a merge.

### 6. Error mapping

There is one `validate(response:data:)`. It decodes Azure's `{ "message": … }` body when present.

| Response | Error |
|---|---|
| `isRejected` (401, 203, 3xx, non-JSON) | `.reauthorizationRequired` |
| 403 | `.providerMessage("The personal access token needs the Code (Read & Write) scope.")` for writes, `.permissionDenied` for reads |
| 404 | `.repositoryUnavailable` |
| Other non-2xx | `.providerMessage(azureMessage ?? "Azure DevOps request failed (HTTP n).")` |

Decoding failures throw `providerMessage("Azure DevOps returned an invalid pull request response.")`. The request URL, headers, and token never appear in messages.

### 7. `AzureReposRepositoryVisibilityService: RepositoryVisibilityProviding`

- **Request:** `GET {hostURL}/{project}/_apis/git/repositories/{repo}?api-version=7.1`. Its `project.visibility` is `public` or `private`. This endpoint needs only the Code (Read) scope. The projects API would need Project & Team (Read), which a Code-only token lacks.
- **Anonymous call (`token == nil`):** sent without Authorization. A private project answers 401, 203, or a sign-in page, which maps to `RepositoryVisibilityProviderError.authorizationRequired`. The controller then retries with the account's token, as it already does.
- **Registration:** `macgitApp.swift` registers it in `RepositoryVisibilityController`'s services as `.azureDevOps`.
- **Effect on gating:** `FeatureAccessResolver`, `FeaturePolicyStore`, and the local policy fallback stay unchanged. The `pullRequests`, `gitFlow`, and `gitLFS` rules now get a real visibility for Azure repositories. When the visibility cannot be resolved (offline, or no token), it stays `.unknown`, which denies access with the existing "Try Again" notice, as for other providers.

### 8. Create sheet for Azure

`CreatePullRequestSheet` hides both `PullRequestParticipantPicker`s when the draft seed's `repository.provider` is `.azureDevOps`, and the controller skips the participant load for Azure. Azure has no assignees, and its reviewer directory needs a broader scope.

Azure rejects a duplicate active pull request with 409 and a message. That message is shown through the existing creation error path.

### 9. Checkout is unchanged

`PullRequestController.checkout` fetches `pull/{n}/head` only for GitHub. For Azure, it checks out the source branch, as for GitLab. Azure publishes only `refs/pull/{id}/merge`, which is a merge preview, not the author's branch.

## Risks / Trade-offs

- **Diffs cost two requests per file.** This is capped at 100 files, run four at a time, and cached for 300 s. Large pull requests show the remaining files without diffs, with a reason.
- **Closed-filter pages can show fewer than 30 rows,** because the request returns all statuses and active ones are filtered out on the client. Paging stays correct because `hasNextPage` comes from the unfiltered response.
- **Merge polling can time out** on a slow Azure queue. The message tells the user to refresh, and nothing is retried automatically.
- **Avatars fall back to initials** for Azure, because Azure avatar URLs need authentication.
- **The visibility change also affects Git Flow and Git LFS gating.** Those features are now gated by real visibility instead of always being denied, so free users with private Azure projects see the Pro prompt instead of the "visibility unavailable" notice.
- **API version 7.1** is the current GA version. A future retirement would need a version bump in one constant.
