# Git Large File Storage Implementation Plan for Commit+

Date: 2026-09-23. Status: first-release implementation added; manual UI and live-provider verification remain outstanding.

Implementation reference: [Git LFS user guide](../git-lfs.md). The delivered UI keeps Git LFS visible in Workspace so new users can discover setup directly. Setup, tracking, and review are presented in that workspace rather than a separate three-page wizard. Explicit LFS downloads show file and byte progress through the CLI progress interface, with an indeterminate fallback. Tracking rules have a source-aware table and preserve raw output for inspection. Existing custom hooks require manual integration. History migration, locking, and pruning remain outside this release.

## 1. What is Git LFS?

Git LFS stores large file content in separate storage. Git keeps a small text file called a **pointer**, containing the content identifier and size. In the working directory, users can open images, videos, and datasets normally once their content has been downloaded.

For example, a 300 MB `demo.mov` has a pointer in the commit and its video content in LFS storage. Anyone cloning the repository needs both Git data and LFS content. LFS suits large binary assets that need versioning; it does not replace `.gitignore` for build output, dependency caches, or files that should not be committed. See the [official introduction](https://git-lfs.com/).

Tracking rules are shared through `.gitattributes`. Adding a rule does not automatically convert files in earlier commits; changing existing history requires a separate migration. The remote provider determines support, storage limits, and bandwidth limits. The app must not infer quotas or promise free LFS storage. See the [tracking documentation](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-track.adoc).

## 2. Product decisions

The first release should let beginners open an existing LFS repository, set up a new one, choose files to track, download content, and commit/push through the existing UI.

| First release | Later phases |
| --- | --- |
| LFS detection, runtime and configuration checks | History rewriting and repository-wide migration |
| One-click Embedded LFS download and Automatic/System/Embedded selection | |
| Guided setup per repository | Server-side file locking/unlocking |
| Tracking rule management and affected-file preview | Cache cleanup/pruning |
| File list and local content availability | Provider-specific quota dashboards |
| Downloads, progress, cancellation, and retry | Hosting an LFS server |
| Stage/commit/push/pull/clone integration | Autonomous AI management or migration of LFS data |
| Pointer recognition in File Status and History | Specialized PSD/video content diffs |

Do not automatically enable LFS, track extensions, commit changes, or rewrite history. This core Git feature requires no additional Firebase/backend services.

## 3. Verified implementation baseline

- `GitStatusService+RevisionBrowser.swift` recognizes pointers by prefix and reports that content has not been downloaded. Replace this with valid pointer detection and actual cache state; a pointer in a commit does not imply that the object is missing locally.
- `GitStatusService.swift` handles Process execution, environments, and output limits. It does not currently expose an LFS progress API for the UI.
- `GitRuntimeManager.swift` manages system Git and the runtime downloaded by the app, including PATH and archive verification. LFS must work with both modes and remain discoverable by child filters/hooks.
- `GitStatusService+Remote.swift` uses credential injection for fetch/push/pull. `GitStatusService+Clone.swift` calls `runGit` directly; audit and extend the clone credential flow when integrating LFS.
- `SyncState.swift` coordinates sync and refresh. `SidebarItem`, `SidebarWorkspaceSection`, and `MainWindowView` are the integration points for the new screen.
- `RepositorySettingsSheetView` has Remote, Pull & Fetch, Git Flow, and Advanced tabs. Keep the LFS file table out of this configuration sheet.
- Repository documentation configures `core.hooksPath .githooks`. Never assume repositories use `.git/hooks` or have no existing hooks.

## 4. UI design

### 4.1. Entry points

Add **Git LFS** to the sidebar's Workspace group when rules/pointers are detected or the user has enabled it for that repository. For repositories without LFS, expose **Set Up Git LFS…** in Repository Settings → Advanced and the Repository menu. Once setup starts, retain the sidebar entry so users can return to it.

In App Settings, beside the Git runtime section, add a **Git LFS Runtime** selector: **Automatic**, **System Git LFS**, and **Embedded Git LFS**. Match the existing `GitRuntimePreference` and `GitRuntimeSettingsSection` interaction patterns. Show the active executable's version, source, path, download size when applicable, and a refresh action. Store the LFS preference and installation only on this Mac, independently of the Git runtime preference. Support all four System/Embedded Git × System/Embedded LFS combinations.

**Embedded LFS is part of the first release.** As with existing Embedded Git, this means a runtime downloaded and managed by Commit+, rather than requiring users to install a package in Terminal. The app does not require Homebrew or sudo.

When the user starts using an LFS feature, resolve and validate the selected runtime before performing the operation:

1. In Automatic mode, use a compatible System Git LFS when available; otherwise use an already installed Embedded Git LFS.
2. If no usable runtime is available, show one native popup for the initiating window: **“Download Git LFS?”** Explain that Commit+ needs Git LFS to manage large files and will install a private copy on this Mac. Show the pinned version and download size. Actions: **Download & Continue** and **Cancel**.
3. One click on **Download & Continue** downloads, verifies, installs, and selects Embedded Git LFS. Show downloading, verifying, and installing states, plus cancellation and Retry on failure. Do not open a browser or require a second installation confirmation.
4. After installation succeeds, revalidate the runtime and return to the pending setup/action with its repository and input preserved. Continue read-only/setup navigation automatically. For a mutation, retain its normal review/confirmation and revalidate repository state; installing the runtime does not authorize a new mutation or bypass an existing confirmation.
5. Cancel leaves repository configuration, hooks, tracking rules, and runtime preference unchanged. Failed installs clean temporary files and preserve any previously working runtime. Do not resume an action in another repository if the user switched repositories while downloading.

Explicit System/Embedded selection must not silently fall back to another source. If System is missing or incompatible, explain the issue and offer **Download & Use Embedded**. If Embedded is selected but missing, offer its download. Persist a new selection only after that runtime is usable. Background repository detection must not display unsolicited download popups; show an inline unavailable state until the user invokes the feature. Coalesce simultaneous download requests across windows into one installation.

Follow the existing `GitRuntimeManager.installEmbeddedRuntime()` pattern: architecture-specific pinned manifest (version, URL, archive size, SHA-256), download to temporary storage, size/hash verification, extraction into a staging directory, executable/version validation, and atomic promotion into versioned app-managed storage. Validate archive paths before extraction and check distribution/signing and license requirements before shipping the manifest. No download URL, version, or checksum should be guessed. Keep the previous valid installation until promotion succeeds.

Compose the selected LFS executable directory into the execution environment for both system and managed Git. Verify that `git lfs`, clean/smudge filters, and pre-push child processes all resolve the selected LFS runtime even when another copy exists elsewhere on PATH. Keep this change scoped to app-launched processes; preserve Git's existing runtime configuration and do not modify the user's shell PATH.

### 4.2. Git LFS screen

Conceptual wireframe; numbers are illustrative:

```text
Git LFS                              [Download Missing] [⋯]
Ready · Current branch: main · Download remote: origin

[Files] [Tracking Rules]

[Search files…                         ] [All states ▾]
File                         Size       Local content
Assets/intro.mov              300 MB     Available
Design/home.psd               120 MB     Not downloaded

2 files · 420 MB referenced by this view
──────────────────────────────────────────────────────────
Download 1 of 3 · 42 MB / 120 MB                     [Cancel]
```

- Use a native table with multiple selection, name/size sorting, search, and context menus. Default to the current checkout/index; do not scan all history whenever the screen opens.
- Distinguish **Available**, **Not downloaded**, **Modified**, **Conflict**, **Checking**, and **Error**. Model cache, working-tree, and transfer metadata separately instead of collapsing them into one boolean.
- Do not display “Uploaded” without evidence that the server has the object. “Available” describes local content only. If the working tree contains a pointer but the object is cached, offer **Restore Content**.
- The selected-file inspector shows the path, content size, copyable OID, status, and Download/Reveal in Finder actions where applicable.
- Label total size as the files referenced by the current view. Local cache size is a separate measurement and does not represent server quota usage.
- Tracking Rules shows each pattern, source `.gitattributes`, directory scope, matching-file count, and Add/Remove actions. Inherited or complex rules may be read-only with **Open Attributes File**; never overwrite rules the app cannot safely interpret.
- Pair status colors with text and icons. Support keyboard navigation, VoiceOver, and narrow windows. Preserve selection during refresh; show the pointing-hand cursor only over actual interactive areas.

### 4.3. Three-step setup

1. **Check the machine and repository:** inspect the LFS executable, version/capabilities, filter configuration, effective hook location, custom hooks, and remote. Show “local setup ready” separately from “remote unverified.” Local inspection must work offline.
2. **Choose files:** add individual files, patterns such as `*.psd`, or directories. Suggest rules based on existing files rather than enabling a broad extension list. Scan on demand, skip `.git` and ignored files, and read size metadata instead of entire files. The default suggestion threshold of 50 MiB is an adjustable/disableable product heuristic, not a Git or provider limit.
3. **Review & Apply:** show the `.gitattributes` diff, affected files, change scope, and hook status. After applying setup/rules, send users to File Status to review, stage, and commit.

For files already tracked as ordinary Git blobs, offer a separate **Convert selected files in the next commit** action. Explain that it stages the selected files again and does not reduce existing history size. Require users to resolve partial staging or conflicts first; do not overwrite an index they are preparing.

### 4.4. Integration with existing UI

- **File Status:** add an LFS badge. **Track with Git LFS…** opens a review sheet with a choice between this file and a pattern. Rule changes appear as ordinary `.gitattributes` changes.
- **Commit:** warn when an LFS file is staged but a required new rule is not. Offer a review action to stage the relevant change; do not automatically stage an entire `.gitattributes` file containing unrelated edits.
- **History / preview:** show an LFS card with actual content size, OID, and **Download for Preview**. Older revisions use an OID-specific cache/temp file without overwriting the working tree. Initially preview only existing supported types within size limits; offer external applications for other types.
- **Push:** retain the existing Push button and show actual LFS upload/Git push progress. Do not report success if the hook/upload fails.
- **Clone:** enable **Download LFS content** by default. When disabled, apply skip-smudge to that operation only without changing global configuration. If Git clone completes but LFS downloading fails, allow opening the repository and Retry Download instead of requiring a full clone again.
- **Pull / checkout:** respect the download policy and existing configuration. If refs/HEAD changed but content downloading failed, report partial completion and refresh actual state before offering retry.
- **Background fetch:** preserve current Git fetch behavior. Do not automatically download gigabytes of LFS content when the app becomes active. Explain the scope of explicit Download actions.

## 5. Git behavior and safety boundaries

### Setup and hooks

Use `git lfs install --local` where appropriate; do not change global configuration by default. Resolve effective `core.hooksPath`, worktree/common directories, and write permissions first. Existing/custom/shared hooks require a “Needs hook integration” state and concrete guidance. Do not use `--force` or concatenate arbitrary scripts automatically. Report Ready only after verifying integration. The default wizard must not modify hook paths outside the repository or shared hook locations. See the [install documentation](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-install.adoc).

### Tracking and converting current files

Use `git lfs track`, `untrack`, and Git's effective attribute checks. Support nested `.gitattributes`, overrides, Unicode, whitespace, and glob characters. Use the CLI's literal filename mode for individual files where supported. Pass argument arrays for every invocation; never construct shell strings from paths.

Tracking changes rules only; converting current files is a separate action. For tracked files, use scoped renormalization after review. For untracked files, use the normal staging flow. Revalidate rules/index/file snapshots immediately before mutation. Do not run repository-wide `git add --renormalize .`. Removing a rule does not automatically turn committed pointers into ordinary Git blobs; explain this in the UI. See the [migration documentation](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-migrate.adoc).

### Downloads and uploads

Separate fetching content into the cache from materializing it in the working tree. `git lfs checkout` uses local objects, does not download content, and does not overwrite modified files. Downloads for the current checkout can use `git lfs pull <remote>`. Selected-file downloads must match paths precisely without accidental wildcard or comma expansion. If the selection cannot be represented safely, explain the limitation instead of silently broadening the download. See [checkout](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-checkout.adoc) and [pull](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-pull.adoc).

Push through the standard pre-push hook; do not prepend `lfs push --all` to every push. Validate hooks/runtime for the correct repository and remote, including existing branch/tag/force-push flows. If uploads succeed but Git push is rejected, retain the upload result and report that Git push did not complete.

Resolve the download remote from the effective upstream/configuration. When ambiguous, let users choose instead of hardcoding origin. Uploads follow the actual push destination. Distinguish authentication failures, unsupported servers, missing objects, quota/bandwidth limits, network loss, and disk exhaustion. Unclassified failures receive a general message with sanitized diagnostic details.

### Credentials and endpoint configuration

The LFS endpoint may differ from the Git remote, including Git over SSH with LFS over HTTPS. Reuse the resolver/Keychain while validating credential origin/path against the actual endpoint. Do not forward a Git host token to another host named in `.lfsconfig`. Keep credential injection alive until child processes/hooks finish. Never write tokens to the repository, diagnostics, or synced configuration. Validate these flows in an early technical spike before promising support for every provider. See the [configuration documentation](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-config.adoc).

### Operations and state

Use one mutation queue per repository/common Git directory, with appropriate locking for shared caches and worktrees. Cancellation must include LFS child processes and wait for termination before cleaning up credentials/temp files. Cancellation does not imply rollback; reload refs, the index, and the working tree. Use CLI-supported progress interfaces where available, with indeterminate progress as a fallback rather than fabricated percentages. Do not treat arbitrary stderr formatting as a stable data contract.

## 6. Proposed architecture

| Component | Responsibility |
| --- | --- |
| New `GitStatusService+LFS.swift` | LFS commands, attribute checks, parsing, and typed results |
| New LFS runtime manager, manifest, preference, and status models integrated with the Git execution context | System discovery, verified Embedded downloads, Automatic/System/Embedded selection, capabilities, and PATH for Git and child processes |
| `GitLFSModels.swift` or separate model files | Setup, rules, file/object state, operation progress, and errors |
| New `RepositoryLFSController` | MainActor state, user actions, revalidation, cancellation, and refresh coordination |
| New `Views/LFS/` | Workspace view, setup sheet, rule editor, preview/recovery UI; presentation and callbacks only |
| Existing `SyncState` and remote/clone services | Operation/progress/credential integration and partial results |
| Existing revision browser / File Status | Badges, pointer metadata, and revision-specific previews |

Prefer JSON where supported, such as `git lfs ls-files --json`. Verify the minimum supported version through capability tests before release. Do not parse human-readable columns under the assumption that filenames contain no spaces. See the [ls-files documentation](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-ls-files.adoc).

Key caches by repository/worktree/ref/index/attributes. Cancel stale loads when changing repositories so repository A's results cannot appear in repository B. Invalidate after mutations through existing notification/SyncState flows. Do not scan history or hash every large file on the main thread. The pointer parser must validate format/OID/size and support valid extensions instead of checking only a prefix.

## 7. Implementation phases

### Phase 1 — Foundation and compatibility validation

- [ ] Establish the minimum Git LFS version through capability tests. Check executable behavior with system and managed Git, on Apple Silicon/Intel if both are distributed.
- [ ] Implement the LFS manifest and verified Embedded installer following the existing Git runtime lifecycle, including safe extraction, atomic promotion, cancellation, failure cleanup, and concurrent-request coalescing.
- [ ] Implement independent Automatic/System/Embedded LFS preferences and validate every Git/LFS runtime combination, including competing executables on PATH.
- [ ] Validate filters/hooks/PATH from the GUI, custom hooksPath, and linked worktrees.
- [ ] Validate Git HTTPS credentials, Git SSH + LFS HTTPS, and endpoints on another host; audit the clone flow.
- [ ] Build models/parsers/setup probes and pointer/command-output fixtures.
- [ ] Extend the existing process runner for progress/cancellation without duplicating the execution system.

Exit criteria: setup can distinguish “Ready / Missing runtime / Needs hook integration / Remote unverified”; authentication cases have defined behavior; cancellation leaves no uncontrolled process continuing to write.

### Phase 2 — Browse LFS repositories and download content

- [ ] Add the sidebar route, Files table, and empty/loading/error states.
- [ ] Implement Download Missing for the current checkout, progress/cancel/retry, and protection for modified files.
- [ ] Add pointer cards in File Status/History and previews using the correct cached OID.
- [ ] Integrate refresh while preserving selection and repository-specific state.

Exit criteria: users can open an existing LFS repository, identify unavailable content, and recover failed downloads without losing local edits.

### Phase 3 — Setup and tracking for beginners

- [ ] Add the setup wizard and first-use **Download & Continue** popup, with progress/cancel/retry and restoration of the initiating repository/action after installation.
- [ ] Add the Git LFS Runtime selector beside Git Runtime in App Settings, with source/version/path, download size, and refresh. Verify explicit selection, missing-runtime recovery, and local-only persistence.
- [ ] Add/remove rules with previews while preserving unrelated comments/rules.
- [ ] Add the Track with Git LFS context menu and on-demand large-file suggestions.
- [ ] Implement selected current-file conversion with guards for partial staging and concurrent edits.
- [ ] Add commit reminders for required staged attributes.

Exit criteria: users can complete setup → choose files → review → stage/commit through the UI, with correct pointers in the index and original content preserved.

### Phase 4 — Complete Git integration and ship the first release

- [ ] Verify push/pull/checkout/clone end to end with configuration-aware remote selection.
- [ ] Add partial-result UI, recovery from clone LFS failures, and sanitized diagnostics.
- [ ] Verify that non-LFS repositories incur no unnecessary latency/network requests.
- [ ] Write a short guide covering pointers, usage, remote costs, and tracking limitations.
- [ ] Complete builds, integration tests, accessibility review, and the manual QA checklist.

The first release is complete only when all four phases meet their exit criteria. A working file-management screen is insufficient if push/clone behavior remains incomplete.

### Phase 5 — Advanced capabilities after user feedback

Add locking/unlocking based on server capabilities; pruning with dry-run, remote verification, and shared-storage checks; and further runtime maintenance improvements beyond the first-release Embedded installer. Treat history migration as a separate project: analyze refs, create recoverable Git and LFS backups, review changed commit IDs, coordinate with collaborators, and require separate push confirmation. Never force-push automatically.

## 8. Testing and acceptance criteria

| Area | Required evidence |
| --- | --- |
| Parsers/rules | Valid/invalid pointers, CRLF, extensions, JSON, Unicode/newline/glob paths, nested attributes |
| Runtime installation | First-use popup, one-click download, offline/retry/cancel, checksum/size mismatch, unsafe archives, executable validation failure, disk/permission failures, previous runtime preservation, and concurrent windows |
| Runtime selection | Automatic/System/Embedded persistence, all Git/LFS combinations, selected runtime wins over competing PATH entries, explicit choice has no silent fallback, and pending actions retain the correct repository |
| Setup | Missing LFS, older versions, existing filters, custom/shared hooks, permission errors, worktrees |
| Tracking | Track/untrack preserves unrelated rules; conversion stays scoped; partial staging is preserved |
| Round trip | Original file → staged pointer → commit → push to local test remote → clone → matching content hash |
| Authentication/network | HTTPS/SSH, endpoints on another host, no token leakage; distinct quota/missing-object/offline/cancellation outcomes |
| Recovery | Partial clone/pull/checkout completion; download retry preserves locally modified files |
| Repository state | Repository changes during loading, two windows/worktrees, selection preserved after refresh |
| Regression | Non-LFS repositories, existing hooks, branch/tag pushes, partial staging, and background fetch retain their behavior |
| UI | Keyboard, VoiceOver, non-color status cues, resizing, progress, and correctly scoped retry actions |

Use temporary repositories and a local LFS remote for integration tests. A local remote does not validate provider authentication or quota behavior. Use controlled test endpoints for credential isolation and remote failures; use test accounts only when provided.

Follow repository rules: run tests and builds sequentially, and do not launch/relaunch the app for verification. If XCTest crashes during bootstrap/Firebase initialization, do not retry; report that tests did not execute. A successful build proves compilation only. Interactive QA must be performed by the user in an appropriate app session, with unverified interactions recorded explicitly.

```bash
rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitLFSIntegrationTests test
rtk proxy xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
rtk git diff --check
```

The test class name is proposed and will be created during implementation. The initial planning task required no build. Implementation validation is recorded in the implementation handoff and Git LFS user guide.
