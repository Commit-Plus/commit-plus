// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func historyRebaseAvailability(in repository: URL) async throws -> HistoryRebaseAvailability {
        guard await inProgressOperation(in: repository) == nil else { return HistoryRebaseAvailability() }
        let branch = try await runGit(arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"], in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = try await runGit(arguments: ["rev-parse", "HEAD"], in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let history = try await runGit(arguments: ["rev-list", "--parents", head], in: repository)
        var parentsByHash: [String: [String]] = [:]
        for line in history.split(separator: "\n") {
            let fields = line.split(separator: " ").map(String.init)
            if let hash = fields.first { parentsByHash[hash] = Array(fields.dropFirst()) }
        }
        var rows: [[String]] = []
        var cursor: String? = head
        while let hash = cursor, let parents = parentsByHash[hash] {
            rows.append([hash] + parents)
            cursor = parents.first
        }
        var result = HistoryRebaseAvailability(branch: branch, head: head,
            ancestors: Set(rows.compactMap(\.first)), reachable: Set(parentsByHash.keys))
        for row in rows {
            guard let hash = row.first, row.count <= 2 else { break }
            result.quickCommits.insert(hash)
        }
        for row in rows where row.count == 2 && result.quickCommits.contains(row[0]) {
            result.squashCommits.insert(row[0])
        }
        return result
    }

    func prepareHistoryRebase(commit: Commit, action: HistoryRebasePlan.Action? = nil,
                              in repository: URL) async throws -> HistoryRebasePlan {
        let availability = try await historyRebaseAvailability(in: repository)
        guard let branch = availability.branch, let head = availability.head else {
            throw GitError.commandFailed("Check out a branch and finish the current Git operation before rebasing.")
        }
        var upstream: String?
        var onto: String?
        if let action {
            guard availability.actions(for: commit).contains(action) else {
                throw GitError.commandFailed("This action requires a non-merge commit on the current branch with no merge commits after it. Squash and fixup also require a parent.")
            }
            let first = action == .squash || action == .fixup ? commit.parents.first! : commit.hash
            let parents = try await runGit(arguments: ["rev-list", "--parents", "-n", "1", first], in: repository)
                .split(whereSeparator: \.isWhitespace).map(String.init)
            upstream = parents.dropFirst().first
        } else if availability.ancestors.contains(commit.hash) {
            upstream = commit.hash
        } else {
            upstream = try await runGit(arguments: ["merge-base", head, commit.hash], in: repository)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            onto = commit.hash
        }
        let range = upstream.map { "\($0)..\(head)" } ?? head
        let historyOptions = action == nil ? [String]() : ["--first-parent"]
        let raw = try await runGit(arguments: ["log", "--reverse", "--topo-order"] + historyOptions + ["--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%at", range], in: repository)
        var entries: [HistoryRebasePlan.Entry] = []
        for line in raw.split(separator: "\n") {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6 else { throw GitError.commandFailed("Unable to read the rebase commits.") }
            let parents = fields[1].split(separator: " ").map(String.init)
            let isSquashParent = (action == .squash || action == .fixup)
                && entries.isEmpty && fields[0] == commit.parents.first
            guard parents.count <= 1 || isSquashParent else {
                throw GitError.commandFailed("This range contains merge commits. Choose a base after the last merge; interactive rewriting currently supports linear history only.")
            }
            let item = Commit(hash: fields[0], parents: parents, message: fields[2], author: fields[3],
                email: fields[4], date: Date(timeIntervalSince1970: Double(fields[5]) ?? 0), refs: [])
            let message = try await runGit(arguments: ["show", "-s", "--format=%B", item.hash], in: repository)
                .trimmingCharacters(in: .newlines)
            entries.append(.init(commit: item, action: item.hash == commit.hash ? action ?? .pick : .pick, message: message))
        }
        guard !entries.isEmpty else { throw GitError.commandFailed("There are no commits to rebase after this commit.") }
        if action == .squash, let index = entries.firstIndex(where: { $0.id == commit.hash }), index > 0 {
            entries[index].squashMessage = entries[index - 1].message + "\n\n" + entries[index].message
        }
        return HistoryRebasePlan(branch: branch, head: head, upstream: upstream, onto: onto,
            originalHashes: entries.map(\.id), quickAction: action, entries: entries)
    }

    func executeHistoryRebase(_ plan: HistoryRebasePlan, in repository: URL) async throws {
        if let error = plan.validationMessage { throw GitError.commandFailed(error) }
        let availability = try await historyRebaseAvailability(in: repository)
        guard availability.head == plan.head, availability.branch == plan.branch else {
            throw GitError.commandFailed("HEAD or the current branch changed. Open Interactive Rebase again.")
        }
        if let action = plan.quickAction {
            guard let selected = plan.entries.first(where: { $0.action == action }),
                  availability.actions(for: selected.commit).contains(action) else {
                throw GitError.commandFailed("These commits are no longer eligible. Open the action again.")
            }
        }
        let status = try await runGit(arguments: ["status", "--porcelain"], in: repository)
        guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.commandFailed("Commit or stash your local changes before rebasing.")
        }
        let directory = try await historyRebaseDirectory(in: repository)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var lines: [String] = []
        for entry in plan.entries {
            if entry.commit.isMerge {
                lines.append("merge -C \(entry.id) \(entry.commit.parents.dropFirst().joined(separator: " "))")
            } else {
                lines.append("\(entry.action.rawValue) \(entry.id)")
            }
            let replacementMessage = entry.action == .reword ? entry.message : entry.squashMessage
            if entry.action == .reword || (entry.action == .squash && !replacementMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                let messageURL = directory.appendingPathComponent(entry.id + ".txt")
                try replacementMessage.write(to: messageURL, atomically: true, encoding: .utf8)
                if entry.action == .squash { lines.append("exec true") }
            }
        }
        let donePath = try await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-path", "rebase-merge/done"], in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let editor = directory.appendingPathComponent("message-editor.sh")
        let editorSource = """
        #!/bin/sh
        set -eu
        commit=$(/usr/bin/awk 'END { if ($1 == "reword" || $1 == "squash") print $2 }' \(Self.rebaseShellQuote(donePath)))
        message=\(Self.rebaseShellQuote(directory.path))/"$commit.txt"
        if [ -n "$commit" ] && [ -f "$message" ]; then
            /bin/cp "$message" "$1"
        fi
        """
        try editorSource.write(to: editor, atomically: true, encoding: .utf8)
        let todo = directory.appendingPathComponent("todo")
        try (lines.joined(separator: "\n") + "\n").write(to: todo, atomically: true, encoding: .utf8)
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_SEQUENCE_EDITOR"] = "/bin/cp \(Self.rebaseShellQuote(todo.path))"
        environment["GIT_EDITOR"] = "/bin/sh \(Self.rebaseShellQuote(editor.path))"
        var arguments = ["-c", "rebase.autoStash=false", "-c", "rebase.updateRefs=false", "-c", "rebase.abbreviateCommands=false",
            "rebase", "--interactive", "--no-rebase-merges", "--no-autosquash", "--no-autostash", "--no-update-refs", "--keep-empty", "--empty=stop"]
        if let onto = plan.onto { arguments += ["--onto", onto] }
        arguments += plan.upstream.map { [$0] } ?? ["--root"]
        do {
            let currentHead = try await runGit(arguments: ["rev-parse", "HEAD"], in: repository)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let currentBranch = try await runGit(arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"], in: repository)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentHead == plan.head, currentBranch == plan.branch else {
                throw GitError.commandFailed("HEAD or the current branch changed. Open Interactive Rebase again.")
            }
            _ = try await runGit(arguments: arguments, in: repository, environment: environment)
        } catch {
            await cleanHistoryRebaseFilesIfFinished(in: repository)
            throw error
        }
        await cleanHistoryRebaseFilesIfFinished(in: repository)
    }

    func resumeHistoryRebase(_ command: String, in repository: URL) async throws {
        guard ["--continue", "--skip", "--abort"].contains(command), await isRebaseInProgress(in: repository) else {
            throw GitError.commandFailed("No rebase is in progress.")
        }
        var environment = ProcessInfo.processInfo.environment
        let editor = try await historyRebaseDirectory(in: repository).appendingPathComponent("message-editor.sh")
        environment["GIT_EDITOR"] = FileManager.default.fileExists(atPath: editor.path)
            ? "/bin/sh \(Self.rebaseShellQuote(editor.path))" : "true"
        do {
            _ = try await runGit(arguments: ["rebase", command], in: repository, environment: environment)
        } catch {
            await cleanHistoryRebaseFilesIfFinished(in: repository)
            throw error
        }
        await cleanHistoryRebaseFilesIfFinished(in: repository)
    }

    private func historyRebaseDirectory(in repository: URL) async throws -> URL {
        let path = try await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-path", "commitplus-rebase"], in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func cleanHistoryRebaseFilesIfFinished(in repository: URL) async {
        guard !(await isRebaseInProgress(in: repository)), let directory = try? await historyRebaseDirectory(in: repository) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func rebaseShellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
