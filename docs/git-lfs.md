# Git LFS in Commit+

Git LFS stores large file content separately from the small pointer committed to Git. Use it for versioned binary assets such as design files, video, and datasets. Keep generated files and caches in `.gitignore` instead.

## Start using Git LFS

1. Open **Git LFS** in the repository sidebar.
2. If a compatible runtime is missing, choose **Download & Continue**. Commit+ downloads the official Git LFS 3.8.0 archive for this Mac, checks its size and SHA-256, and installs a private copy. Homebrew and administrator access are not required.
3. Choose **Set Up Git LFS…** to configure this repository's filters and pre-push hook.
4. Open **Tracking Rules**, enter a pattern such as `*.psd`, review it, and apply. For an individual filename, enable **Exact filename**. You can also start from a file's **Track with Git LFS…** context menu in File Status.
5. Review and stage `.gitattributes` and the affected files in File Status, then commit and push normally.

The setup action preserves custom hooks. Repositories with a custom `core.hooksPath` require manual integration using `git lfs install --local --manual`. Refresh after integrating the hook. Commit+ does not overwrite shared hooks.

## Choose the runtime

**Settings → Git → Git LFS Installation** offers Automatic, System, and Embedded independently of Git Runtime. Automatic prefers a compatible system installation. System Git LFS must be version 3.8 or later. Downloading Embedded LFS selects it after successful installation. Settings and binaries stay local to this Mac.

The selected runtime is also used by clean/smudge filters and pre-push hooks, including when Embedded Git contains another `git-lfs` executable. A cancelled or failed installation preserves the previous runtime and preference. Refresh Git LFS Information after installing or changing a system executable externally.

## Existing files and history

Adding a rule does not rewrite earlier commits. To convert a file already stored as a normal Git blob, choose **Convert Existing File…** under Tracking Rules. Review **Convert & Stage**, then commit the staged pointer and relevant attributes changes. Commit+ rejects files with existing staged changes to preserve partial staging.

This conversion does not shrink existing history. History migration, server-side file locking, cache pruning, and provider quota dashboards are outside this release.

## Download and inspect content

- **Download Missing** downloads content for the current checkout using the selected remote and existing LFS include/exclude settings.
- **Download Selected** uses an explicit file selection. Filenames that cannot be represented safely in the CLI's include-filter syntax are rejected rather than broadening the download.
- **Restore Content** materializes cached content without downloading. Modified files are preserved.
- File states describe local content, not proof that the remote has received an object.
- **History → Browse Repository at Revision** recognizes valid LFS pointers, previews verified cached content within the existing 2 MB limit, and offers **Download for Preview**. Downloads for old revisions only change the cache, never the working tree.

The Files table supports search, sorting, state filtering, and multiple selection. Explicit downloads show per-file byte progress when reported by the CLI, with an indeterminate fallback. Tracking Rules lists each pattern and source; inherited and excluded rules remain read-only in the table. Find Large Files scans metadata on demand, excludes ignored files, and defaults to a 50 MiB suggestion threshold. That threshold is a UI suggestion, not a provider upload limit.

## Clone and recovery

Clone has a **Download LFS content** option. Git data is cloned first. If LFS setup or downloading fails, the completed clone is retained; choose **Open Cloned Repository**, **Retry LFS Download**, or **Download Git LFS & Continue** when a runtime is missing. Disabling LFS downloading leaves pointers for later setup/download.

Ordinary push uses the repository's LFS pre-push hook. Background Git fetch does not trigger an additional LFS download. Authentication, network, quota, missing-object, and disk-space failures are surfaced with recovery guidance. Remote storage and bandwidth limits are controlled by the hosting provider.

## Validation

Automated coverage includes pointer validation, unusual filenames, include-filter safety, credential host isolation, custom hook preservation, concurrent edits, partial staging, local push/clone/download round trips, runtime selection, and verified Embedded installation. Integration tests use `COMMITPLUS_TEST_LFS` for a test executable; the installer test uses `COMMITPLUS_TEST_LFS_ARCHIVE` for the official archive matching the host architecture. Neither test downloads or changes the user's runtime preference.

Interactive UI behavior and live provider authentication/quota responses require separate manual verification. Recursive submodule LFS setup/download is not coordinated by the root repository's LFS screen; open each submodule repository to manage its LFS state.

Sources: [Git LFS](https://git-lfs.com/), [official command documentation](https://github.com/git-lfs/git-lfs/tree/v3.8.0/docs/man), [pinned runtime release](https://github.com/git-lfs/git-lfs/releases/tag/v3.8.0).
