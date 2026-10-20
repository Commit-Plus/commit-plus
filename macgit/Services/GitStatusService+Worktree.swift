//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation

enum WorktreeAddTarget: Sendable, Equatable {
    case existingBranch(String)
    case newBranch(name: String, base: String?)
}

extension GitStatusService {
    func worktreePath(for branch: String, in repositoryURL: URL) async throws -> URL? {
        let output = try await runGit(
            arguments: ["worktree", "list", "--porcelain"],
            in: repositoryURL
        )
        return parseWorktreePorcelain(output).first(where: { $0.branch == branch })?.path
    }

    /// Branches checked out in worktrees other than `repositoryURL` itself.
    func worktreeBranches(in repositoryURL: URL) async -> Set<String> {
        let output = (try? await runGit(arguments: ["worktree", "list", "--porcelain"], in: repositoryURL)) ?? ""
        // git prints real paths, so resolve symlinks before comparing with the opened URL.
        let currentPath = normalizedWorktreePath(repositoryURL.resolvingSymlinksInPath())
        return Set(parseWorktreePorcelain(output)
            .filter { normalizedWorktreePath($0.path.resolvingSymlinksInPath()) != currentPath }
            .compactMap(\.branch))
    }

    /// The main worktree is always the first entry, including for bare repositories and submodules.
    func mainWorktreePath(in repositoryURL: URL) async -> URL? {
        let output = (try? await runGit(arguments: ["worktree", "list", "--porcelain"], in: repositoryURL)) ?? ""
        return parseWorktreePorcelain(output).first?.path
    }

    /// The branch checked out in the worktree, or its HEAD commit when detached.
    func worktreeHistoryReference(for worktreePath: URL, in repositoryURL: URL) async -> String? {
        let output = (try? await runGit(arguments: ["worktree", "list", "--porcelain"], in: repositoryURL)) ?? ""
        let path = normalizedWorktreePath(worktreePath)
        guard let entry = parseWorktreePorcelain(output).first(where: { normalizedWorktreePath($0.path) == path }) else {
            return nil
        }
        return entry.branch ?? (entry.head.isEmpty ? nil : entry.head)
    }

    func worktrees(in repositoryURL: URL) async -> [WorktreeEntry] {
        let output = (try? await runGit(arguments: ["worktree", "list", "--porcelain"], in: repositoryURL)) ?? ""
        let parsed = parseWorktreePorcelain(output)

        var dirtyCounts: [URL: Int] = [:]
        await withTaskGroup(of: (URL, Int).self) { group in
            for entry in parsed {
                group.addTask {
                    let count = await self.dirtyCount(in: entry.path)
                    return (entry.path, count)
                }
            }

            for await (path, count) in group {
                dirtyCounts[path] = count
            }
        }

        return parsed.map { entry in
            WorktreeEntry(
                path: entry.path,
                head: entry.head,
                branch: entry.branch,
                isLocked: entry.isLocked,
                dirtyCount: dirtyCounts[entry.path] ?? -1,
                label: nil
            )
        }
    }

    func dirtyCount(in worktreePath: URL) async -> Int {
        guard let output = try? await runGit(arguments: ["status", "--porcelain"], in: worktreePath) else {
            return -1
        }

        return output.split(separator: "\n").count
    }

    func gitCommonDirectory(in repositoryURL: URL) async throws -> URL {
        let output = try await runGit(
            arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            in: repositoryURL
        )
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedWorktreeURL(from: path)
    }

    func worktreesWithLabels(in repositoryURL: URL) async -> [WorktreeEntry] {
        let entries = await worktrees(in: repositoryURL)
        guard let gitDirectory = try? await gitCommonDirectory(in: repositoryURL) else {
            return entries
        }

        let store = WorktreeLabelStore()
        let labels = (try? store.prune(validPaths: Set(entries.map(\.path)), in: gitDirectory))
            ?? store.labels(in: gitDirectory)

        return entries.map { entry in
            var labeled = entry
            labeled.label = labels[WorktreeLabelStore.key(for: entry.path)]
            return labeled
        }
    }

    func setWorktreeLabel(_ label: String?, for path: URL, in repositoryURL: URL) async throws {
        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().setLabel(label, for: path, in: gitDirectory)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func removeWorktreeLabel(for path: URL, in repositoryURL: URL) async throws {
        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().removeLabel(for: path, in: gitDirectory)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func addWorktree(
        at path: URL,
        target: WorktreeAddTarget,
        label: String?,
        in repositoryURL: URL,
        notifyChange: Bool = true
    ) async throws {
        var arguments = ["worktree", "add"]
        switch target {
        case .existingBranch(let branch):
            arguments.append(path.path)
            arguments.append(branch)
        case .newBranch(let name, let base):
            arguments.append("-b")
            arguments.append(name)
            arguments.append(path.path)
            if let base, !base.isEmpty {
                arguments.append(base)
            }
        }

        _ = try await runGit(arguments: arguments, in: repositoryURL)

        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
            try WorktreeLabelStore().setLabel(label, for: path, in: gitDirectory)
        }

        if notifyChange {
            await postRepositoryDidChange(for: repositoryURL)
        }
    }

    func removeWorktree(
        at path: URL,
        force: Bool,
        in repositoryURL: URL,
        notifyChange: Bool = true
    ) async throws {
        if isMainWorktree(path, repositoryURL: repositoryURL) {
            throw GitError.commandFailed("The main worktree cannot be removed.")
        }

        var arguments = ["worktree", "remove"]
        if force {
            arguments.append("--force")
            arguments.append("--force")
        }
        arguments.append(path.path)

        _ = try await runGit(arguments: arguments, in: repositoryURL)

        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().removeLabel(for: path, in: gitDirectory)
        if notifyChange {
            await postRepositoryDidChange(for: repositoryURL)
        }
    }

    func repairWorktreeLocation(from oldPath: URL, to newPath: URL, in repositoryURL: URL) async throws {
        let normalizedNewPath = newPath.standardizedFileURL
        if !FileManager.default.fileExists(atPath: normalizedNewPath.path) {
            throw GitError.commandFailed("The selected worktree folder does not exist.")
        }

        _ = try await runGit(arguments: ["worktree", "repair", normalizedNewPath.path], in: repositoryURL)

        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().moveLabel(from: oldPath, to: normalizedNewPath, in: gitDirectory)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func lockWorktree(at path: URL, reason: String?, in repositoryURL: URL) async throws {
        try throwIfMainWorktree(path, repositoryURL: repositoryURL, action: "locked")

        var arguments = ["worktree", "lock"]
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedReason.isEmpty {
            arguments.append("--reason")
            arguments.append(trimmedReason)
        }
        arguments.append(path.path)

        _ = try await runGit(arguments: arguments, in: repositoryURL)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func unlockWorktree(at path: URL, in repositoryURL: URL) async throws {
        try throwIfMainWorktree(path, repositoryURL: repositoryURL, action: "unlocked")

        _ = try await runGit(arguments: ["worktree", "unlock", path.path], in: repositoryURL)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func pruneWorktrees(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["worktree", "prune"], in: repositoryURL)

        let entries = await worktrees(in: repositoryURL)
        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().prune(validPaths: Set(entries.map(\.path)), in: gitDirectory)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func moveWorktree(from oldPath: URL, to newPath: URL, in repositoryURL: URL) async throws {
        try throwIfMainWorktree(oldPath, repositoryURL: repositoryURL, action: "moved")

        let normalizedNewPath = newPath.standardizedFileURL
        if normalizedNewPath.path.isEmpty {
            throw GitError.commandFailed("Target path is required.")
        }
        if FileManager.default.fileExists(atPath: normalizedNewPath.path) {
            throw GitError.commandFailed("Target path already exists.")
        }

        _ = try await runGit(arguments: ["worktree", "move", oldPath.path, normalizedNewPath.path], in: repositoryURL)

        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().moveLabel(from: oldPath, to: normalizedNewPath, in: gitDirectory)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func checkoutBranch(
        _ branch: String,
        inWorktree worktreePath: URL,
        force: Bool,
        repositoryURL: URL
    ) async throws {
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBranch.isEmpty {
            throw GitError.commandFailed("Branch name is required.")
        }

        var arguments = ["checkout"]
        if force {
            arguments.append("--force")
        }
        arguments.append(trimmedBranch)

        _ = try await runGit(arguments: arguments, in: worktreePath)
        await postRepositoryDidChange(for: repositoryURL)
    }

    struct ParsedWorktree {
        let path: URL
        let head: String
        let branch: String?
        let isLocked: Bool
    }

    func parseWorktreePorcelain(_ output: String) -> [ParsedWorktree] {
        var entries: [ParsedWorktree] = []
        var path: URL?
        var head = ""
        var branch: String?
        var isLocked = false

        func flushCurrentEntry() {
            guard let path else { return }
            entries.append(
                ParsedWorktree(
                    path: path,
                    head: String(head.prefix(7)),
                    branch: branch,
                    isLocked: isLocked
                )
            )
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.isEmpty {
                flushCurrentEntry()
                path = nil
                head = ""
                branch = nil
                isLocked = false
                continue
            }

            if line.hasPrefix("worktree ") {
                flushCurrentEntry()
                path = normalizedWorktreeURL(from: String(line.dropFirst("worktree ".count)))
                head = ""
                branch = nil
                isLocked = false
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "locked" || line.hasPrefix("locked ") {
                isLocked = true
            }
        }

        flushCurrentEntry()

        return entries
    }

    private func normalizedWorktreeURL(from path: String) -> URL {
        let cleanPath = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
        return URL(fileURLWithPath: cleanPath, isDirectory: false)
    }

    private func isMainWorktree(_ path: URL, repositoryURL: URL) -> Bool {
        normalizedWorktreePath(path) == normalizedWorktreePath(repositoryURL)
    }

    private func normalizedWorktreePath(_ url: URL) -> String {
        WorktreeLabelStore.key(for: url)
    }

    private func throwIfMainWorktree(_ path: URL, repositoryURL: URL, action: String) throws {
        if isMainWorktree(path, repositoryURL: repositoryURL) {
            throw GitError.commandFailed("The main worktree cannot be \(action).")
        }
    }

    @MainActor
    private func postRepositoryDidChange(for repositoryURL: URL) {
        NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
    }
}
