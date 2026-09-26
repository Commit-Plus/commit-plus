// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func largeLFSCandidates(minimumBytes: Int64, in repository: URL) async throws -> [GitLFSCandidate] {
        let output = try await runGit(arguments: ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], in: repository)
        let paths = Set(output.split(separator: "\0").map(String.init))
        guard paths.count <= 50_000 else { throw GitError.commandFailed("This repository is too large to scan at once. Track a filename or pattern directly.") }
        var candidates: [GitLFSCandidate] = []
        for path in paths {
            try Task.checkCancellation()
            let url = repository.appendingPathComponent(path)
            guard url.resolvingSymlinksInPath().path.hasPrefix(repository.resolvingSymlinksInPath().path + "/"),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size >= minimumBytes else { continue }
            candidates.append(GitLFSCandidate(path: path, size: Int64(size)))
        }
        let tracked = try await lfsPaths(candidates.map(\.path), in: repository)
        return candidates.filter { !tracked.contains($0.path) }.sorted { $0.size > $1.size }
    }

    func lfsPaths(_ paths: [String], cached: Bool = false, in repository: URL) async throws -> Set<String> {
        var result = Set<String>()
        for offset in stride(from: 0, to: paths.count, by: 200) {
            let batch = Array(paths[offset..<min(offset + 200, paths.count)])
            let output = try await runGit(arguments: ["check-attr", "-z"] + (cached ? ["--cached"] : []) + ["filter", "--"] + batch, in: repository)
            let fields = output.split(separator: "\0", omittingEmptySubsequences: false)
            for index in stride(from: 0, to: max(0, fields.count - 2), by: 3) where fields[index + 2] == "lfs" {
                result.insert(String(fields[index]))
            }
        }
        return result
    }

    func validateLFSCommitAttributes(in repository: URL) async throws {
        let output = try await runGit(arguments: ["diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"], in: repository)
        let paths = output.split(separator: "\0").map(String.init)
        guard !paths.isEmpty else { return }
        let working = try await lfsPaths(paths, in: repository)
        guard !working.isEmpty else { return }
        let staged = try await lfsPaths(Array(working), cached: true, in: repository)
        guard working.isSubset(of: staged) else {
            throw GitError.commandFailed("Some staged files use an unstaged Git LFS rule. Review and stage the relevant .gitattributes changes in File Status before committing.")
        }
    }

    func runLFS(_ arguments: [String], in repository: URL, environment: [String: String]? = nil, onProgress: (@Sendable (GitLFSTransferProgress) -> Void)? = nil) async throws -> String {
        let executable = try await lfsRuntime.executable()
        let context = try await gitExecutionContext(environment: environment ?? ProcessInfo.processInfo.environment)
        var processEnvironment = context.environment
        let progressFile = FileManager.default.temporaryDirectory.appendingPathComponent("commitplus-lfs-progress-\(UUID())")
        var observer: Task<Void, Never>?
        if let onProgress, FileManager.default.createFile(atPath: progressFile.path, contents: Data(), attributes: [.posixPermissions: 0o600]) {
            processEnvironment["GIT_LFS_PROGRESS"] = progressFile.path
            observer = GitLFSProgressReader.observe(file: progressFile, update: onProgress)
        }
        defer {
            observer?.cancel()
            try? FileManager.default.removeItem(at: progressFile)
        }
        // Execute the selected binary directly; filters/hooks receive the same PATH.
        do {
            let output = try await runProcessRaw(executableURL: executable, arguments: arguments, in: repository,
                environment: processEnvironment, outputByteLimit: 16_000_000)
            return String(decoding: output, as: UTF8.self)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw GitError.commandFailed(GitLFSErrorMessage.describe(error))
        }
    }

    func lfsSnapshot(in repository: URL) async throws -> GitLFSSnapshot {
        let output = try await runLFS(["ls-files", "--json"], in: repository)
        var files = try JSONDecoder().decode(GitLFSFileList.self, from: Data(output.utf8)).files ?? []
        let changed = try await runGit(arguments: ["diff", "--name-only", "-z", "--no-ext-diff", "--no-textconv"], in: repository)
        let changedPaths = Set(changed.split(separator: "\0").map(String.init))
        let conflicts = try await runGit(arguments: ["diff", "--name-only", "--diff-filter=U", "-z"], in: repository)
        let conflictPaths = Set(conflicts.split(separator: "\0").map(String.init))
        for index in files.indices {
            if conflictPaths.contains(files[index].name) { files[index].modification = "Conflict" }
            else if changedPaths.contains(files[index].name) { files[index].modification = "Modified" }
        }
        let rules = try await runLFS(["track"], in: repository)
        let branch = await currentBranch(in: repository) ?? "Detached HEAD"
        let remotes = await remotes(in: repository)
        let upstream = try? await runGit(arguments: ["config", "--get", "branch.\(branch).remote"], in: repository).trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = upstream.flatMap { remotes.contains($0) ? $0 : nil } ?? (remotes.count == 1 ? remotes.first : nil)
        let issue = try await lfsSetupIssue(in: repository)
        return GitLFSSnapshot(files: files, rules: rules, branch: branch, remotes: remotes, suggestedRemote: remote, setupIssue: issue)
    }

    private func lfsHookURL(in repository: URL) async throws -> URL {
        let path = try await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-path", "hooks/pre-push"], in: repository)
        return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: repository).standardizedFileURL
    }

    func lfsSetupIssue(in repository: URL) async throws -> String? {
        let hook = try await lfsHookURL(in: repository)
        let contents = (try? String(contentsOf: hook, encoding: .utf8)) ?? ""
        let filter = (try? await runGit(arguments: ["config", "--get", "filter.lfs.process"], in: repository)) ?? ""
        guard filter.contains("git-lfs filter-process") else { return "Git LFS filters need setup in this repository." }
        guard contents.contains("# Commit+ LFS hook dispatcher v1") || contents.contains("git lfs pre-push") || contents.contains("git-lfs pre-push") else {
            return contents.isEmpty ? "The Git LFS pre-push hook is missing." : "Git LFS needs to be connected to the existing pre-push hook."
        }
        guard FileManager.default.isExecutableFile(atPath: hook.path) else { return "The pre-push hook is not executable." }
        return nil
    }

    func setupLFS(in repository: URL) async throws {
        let key = try await acquireLFSMutation(in: repository)
        defer { lfsMutations.remove(key) }
        let scope = (try? await runGit(arguments: ["config", "--bool", "extensions.worktreeConfig"], in: repository))?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true" ? "--worktree" : "--local"
        let configKeys = ["filter.lfs.clean", "filter.lfs.smudge", "filter.lfs.process", "filter.lfs.required", "core.hooksPath"]
        let configOutput = try await runGit(arguments: ["config", scope, "--null", "--list"], in: repository)
        var previousConfig: [String: [String]] = [:]
        for record in configOutput.split(separator: "\0") {
            let fields = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(fields[0])
            guard configKeys.contains(name) else { continue }
            previousConfig[name, default: []].append(fields.count == 2 ? String(fields[1]) : "true")
        }
        let hook = try await lfsHookURL(in: repository)
        let contents = (try? String(contentsOf: hook, encoding: .utf8)) ?? ""
        // Repeated setup must not wrap our own dispatcher again.
        if contents.contains("# Commit+ LFS hook dispatcher v1") {
            _ = try await runLFS(["install", scope, "--skip-repo"], in: repository)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
            return
        }
        let configuredPath = (try? await runGit(arguments: ["config", "--path", "--get", "core.hooksPath"], in: repository))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Keep relative hooks paths relative to Git's working directory, including other worktrees.
        let originalDirectory = configuredPath.isEmpty ? hook.deletingLastPathComponent().path : configuredPath
        let commonPath = try await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"], in: repository)
        let directory = URL(fileURLWithPath: commonPath.trimmingCharacters(in: .whitespacesAndNewlines))
            .appendingPathComponent("commitplus-lfs-hooks/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            // Dispatch standard hooks even if absent today, so adding a hook to the original directory still works.
            let names = Set([
                "applypatch-msg", "pre-applypatch", "post-applypatch", "pre-commit", "pre-merge-commit",
                "prepare-commit-msg", "commit-msg", "post-commit", "pre-rebase", "post-checkout", "post-merge",
                "pre-push", "pre-receive", "update", "proc-receive", "post-receive", "post-update",
                "reference-transaction", "push-to-checkout", "pre-auto-gc", "post-rewrite",
                "sendemail-validate", "fsmonitor-watchman", "p4-changelist", "p4-prepare-changelist",
                "p4-post-changelist", "p4-pre-submit", "post-index-change"
            ])
            for name in names {
                let original = originalDirectory + "/" + name
                let existingURL = URL(fileURLWithPath: original, relativeTo: repository)
                let existing = (try? String(contentsOf: existingURL, encoding: .utf8)) ?? ""
                let alreadyRunsLFS = FileManager.default.isExecutableFile(atPath: existingURL.path)
                    && (existing.contains("git lfs " + name) || existing.contains("git-lfs " + name))
                let lfsHook = ["pre-push", "post-checkout", "post-merge", "post-commit"].contains(name) && !alreadyRunsLFS
                let script = Self.lfsHookDispatcher(original: original, name: name, includeLFS: lfsHook)
                let destination = directory.appendingPathComponent(name)
                try script.write(to: destination, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            }
            _ = try await runLFS(["install", scope, "--skip-repo"], in: repository)
            // Publish only after the complete hook directory and filters are ready.
            _ = try await runGit(arguments: ["config", scope, "core.hooksPath", directory.path], in: repository)
        } catch {
            let setupError = error
            let savedConfig = previousConfig
            // An unstructured task can roll back even when setup's task was cancelled.
            try await Task {
                let current = try await self.runGit(arguments: ["config", scope, "--null", "--list"], in: repository)
                let currentKeys = Set(current.split(separator: "\0").map { String($0.prefix(while: { $0 != "\n" })) })
                for name in configKeys {
                    if currentKeys.contains(name) {
                        _ = try await self.runGit(arguments: ["config", scope, "--unset-all", name], in: repository)
                    }
                    for value in savedConfig[name] ?? [] {
                        _ = try await self.runGit(arguments: ["config", scope, "--add", name, value], in: repository)
                    }
                }
            }.value
            try? FileManager.default.removeItem(at: directory)
            throw setupError
        }
    }

    private static func lfsHookDispatcher(original: String, name: String, includeLFS: Bool) -> String {
        let quoted = "'" + original.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let header = "#!/bin/sh\n# Commit+ LFS hook dispatcher v1\noriginal=" + quoted + "\n"
        guard includeLFS else {
            return header + "if [ -x \"$original\" ]; then exec \"$original\" \"$@\"; fi\nexit 0\n"
        }
        if name == "pre-push" {
            // Both consumers require the complete ref-update stream. Preserve hook arguments and failure status.
            return header + """
            input=$(mktemp "${TMPDIR:-/tmp}/commitplus-lfs.XXXXXXXX") || exit 1
            trap 'rm -f "$input"' EXIT
            trap 'exit 1' HUP INT TERM
            cat > "$input" || exit 1
            if [ -x "$original" ]; then
                "$original" "$@" < "$input" || exit $?
            fi
            git lfs pre-push "$@" < "$input"
            """ + "\n"
        }
        return header + """
        if [ -x "$original" ]; then
            "$original" "$@" || exit $?
        fi
        git lfs \(name) "$@"
        """ + "\n"
    }

    func reviewLFSTracking(pattern: String, literal: Bool, removing: Bool, in repository: URL) async throws -> GitLFSTrackingReview {
        guard !pattern.isEmpty, !pattern.hasPrefix("-"), !pattern.contains("\n"), !pattern.contains("\r"), !pattern.contains("\0"),
              !pattern.hasPrefix("/"), !pattern.split(separator: "/").contains("..") else {
            throw GitError.commandFailed("Enter a repository-relative file or pattern, without newlines or a leading dash.")
        }
        let attributes = try readLFSAttributes(in: repository)
        let preview: String
        if removing { preview = "Remove the root tracking rule: \(pattern)\nExisting committed pointers and history will not be converted." }
        else {
            preview = try await runLFS(["track", "--dry-run"] + (literal ? ["--filename"] : []) + [pattern], in: repository)
        }
        return GitLFSTrackingReview(pattern: pattern, literal: literal, removing: removing, attributes: attributes, preview: preview)
    }

    private func readLFSAttributes(in repository: URL) throws -> Data? {
        let url = repository.appendingPathComponent(".gitattributes")
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values?.isSymbolicLink != true, (values?.fileSize ?? 0) < 2_000_000 else {
            throw GitError.commandFailed("Open .gitattributes manually: it is a symbolic link or too large to edit safely.")
        }
        return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    func applyLFSTracking(_ review: GitLFSTrackingReview, in repository: URL) async throws {
        let key = try await acquireLFSMutation(in: repository)
        defer { lfsMutations.remove(key) }
        guard try readLFSAttributes(in: repository) == review.attributes else {
            throw GitError.commandFailed(".gitattributes changed. Review the tracking rule again.")
        }
        _ = try await runLFS([review.removing ? "untrack" : "track"] + (review.literal ? ["--filename"] : []) + [review.pattern], in: repository)
    }

    func downloadLFS(remote: String, in repository: URL, credentialResolver: GitProviderCredentialResolver?, paths: [String]? = nil, onProgress: (@Sendable (GitLFSTransferProgress) -> Void)? = nil) async throws {
        let key = try await acquireLFSMutation(in: repository)
        defer { lfsMutations.remove(key) }
        guard !remote.isEmpty, !remote.hasPrefix("-"), await remotes(in: repository).contains(remote) else {
            throw GitError.commandFailed("Choose an existing download remote.")
        }
        let injection = try await credentialInjection(for: remote, in: repository, credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(), sshCredentialInjector: TemporaryGitSSHCredentialInjector())
        defer { injection?.cleanup() }
        var arguments = ["pull"]
        if let paths {
            arguments += ["--include=" + (try Self.lfsIncludePaths(paths)), "--exclude="]
        }
        arguments.append(remote)
        _ = try await runLFS(arguments, in: repository, environment: injection?.environment, onProgress: onProgress)
    }

    func restoreLFS(in repository: URL) async throws {
        let key = try await acquireLFSMutation(in: repository)
        defer { lfsMutations.remove(key) }
        _ = try await runLFS(["checkout"], in: repository)
    }

    nonisolated static func lfsIncludePaths(_ paths: [String]) throws -> String {
        guard !paths.isEmpty, paths.allSatisfy({ path in
            !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix("#") && !path.split(separator: "/").contains("..")
                && path == path.trimmingCharacters(in: .whitespacesAndNewlines)
                && !path.contains(where: { "*?[],!\\\n\r\0".contains($0) })
        }) else {
            throw GitError.commandFailed("This selection contains filenames that cannot be represented by LFS include filters. Use Download Missing instead.")
        }
        return paths.map { "/" + $0 }.joined(separator: ",")
    }

    func downloadLFSPreview(path: String, revision: String, remote: String, in repository: URL, credentialResolver: GitProviderCredentialResolver? = nil) async throws {
        try Self.validateBrowserObjectID(revision)
        let include = try Self.lfsIncludePaths([path])
        guard !remote.hasPrefix("-"), await remotes(in: repository).contains(remote) else {
            throw GitError.commandFailed("This filename cannot be downloaded individually. Download its revision with Git LFS from Terminal.")
        }
        let key = try await acquireLFSMutation(in: repository)
        defer { lfsMutations.remove(key) }
        let injection = try await credentialInjection(for: remote, in: repository, credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(), sshCredentialInjector: TemporaryGitSSHCredentialInjector())
        defer { injection?.cleanup() }
        // fetch changes only the cache, never the index or working tree.
        var environment = injection?.environment ?? ProcessInfo.processInfo.environment
        let count = Int(environment["GIT_CONFIG_COUNT"] ?? "") ?? 0
        environment["GIT_CONFIG_COUNT"] = String(count + 1)
        environment["GIT_CONFIG_KEY_\(count)"] = "lfs.fetchrecentalways"
        environment["GIT_CONFIG_VALUE_\(count)"] = "false"
        _ = try await runLFS(["fetch", "--include=" + include, "--exclude=", remote, revision], in: repository, environment: environment)
    }

    func reviewLFSConversion(path: String, in repository: URL) async throws -> GitLFSConversionReview {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\0") else {
            throw GitError.commandFailed("Select a file inside this repository.")
        }
        let file = repository.appendingPathComponent(path)
        let root = repository.resolvingSymlinksInPath().path + "/"
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, file.resolvingSymlinksInPath().path.hasPrefix(root) else {
            throw GitError.commandFailed("Only regular files inside this repository can be converted.")
        }
        let attributes = try await runGit(arguments: ["check-attr", "-z", "filter", "--", path], in: repository)
        guard attributes.split(separator: "\0").last == "lfs" else {
            throw GitError.commandFailed("Add a Git LFS tracking rule for this file first.")
        }
        let staged = try await runGit(arguments: ["--literal-pathspecs", "diff", "--cached", "--name-only", "-z", "--", path], in: repository)
        guard staged.isEmpty else { throw GitError.commandFailed("This file already has staged changes. Commit or unstage it before converting, so partial staging is preserved.") }
        let index = try await runGit(arguments: ["--literal-pathspecs", "ls-files", "--stage", "-z", "--", path], in: repository)
        guard !index.split(separator: "\0").contains(where: { !$0.contains(" 0\t") }) else {
            throw GitError.commandFailed("Resolve this file's merge conflict before converting it.")
        }
        let hash = try await runGit(arguments: ["hash-object", "--no-filters", "--", path], in: repository)
        return GitLFSConversionReview(path: path, contentHash: hash, indexEntry: index, attributes: attributes)
    }

    func convertLFS(_ review: GitLFSConversionReview, in repository: URL) async throws {
        let key = try await acquireLFSMutation(in: repository)
        defer { lfsMutations.remove(key) }
        let current = try await reviewLFSConversion(path: review.path, in: repository)
        guard current.contentHash == review.contentHash, current.indexEntry == review.indexEntry, current.attributes == review.attributes else {
            throw GitError.commandFailed("The file or index changed. Review the conversion again.")
        }
        _ = try await runGit(arguments: ["--literal-pathspecs", "add"] + (review.indexEntry.isEmpty ? [] : ["--renormalize"]) + ["--", review.path], in: repository)
    }

    private func acquireLFSMutation(in repository: URL) async throws -> String {
        let key = try await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"], in: repository).trimmingCharacters(in: .whitespacesAndNewlines)
        guard lfsMutations.insert(key).inserted else { throw GitError.commandFailed("Another Git LFS operation is running for this repository. Wait for it to finish.") }
        return key
    }
}
