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

extension GitStatusService {
    func supportsGitSubtree(in repositoryURL: URL) async -> Bool {
        do {
            _ = try await runGit(arguments: ["subtree", "-h"], in: repositoryURL)
            return true
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("usage: git subtree") {
                return true
            }
            return false
        }
    }

    func subtreeOperationDecision(in repositoryURL: URL) async throws -> SubtreeOperationDecision {
        guard await supportsGitSubtree(in: repositoryURL) else {
            return SubtreeOperationDecision(
                isAllowed: false,
                blockingPaths: [],
                message: SubtreeOperationPolicy.unavailableMessage
            )
        }

        let status = try await runGit(
            arguments: ["status", "--porcelain=v1", "-z"],
            in: repositoryURL
        )
        return SubtreeOperationPolicy.decision(forStatus: status)
    }

    func addSubtree(
        _ request: SubtreeLinkRequest,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?,
        registry: any GitSubtreeRegistryProtocol = GitSubtreeRegistry()
    ) async throws -> GitSubtreeEntry {
        try await rejectBlockedSubtreeOperation(in: repositoryURL)
        let existing = try await registry.entries(in: repositoryURL)
        let entry = try validatedNewSubtreeEntry(request, existing: existing, in: repositoryURL)
        let injection = try await credentialInjection(
            for: entry.repository,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(),
            sshCredentialInjector: TemporaryGitSSHCredentialInjector()
        )
        defer { injection?.cleanup() }

        var arguments = [
            "subtree",
            "add",
            "--prefix=\(entry.path)",
            entry.repository,
            entry.branch
        ]
        if entry.squash {
            arguments.append("--squash")
        }
        try removeEmptySubtreePrefixIfNeeded(path: entry.path, in: repositoryURL)
        if let environment = gitEnvironment(for: entry.repository, injection: injection) {
            _ = try await runGit(arguments: arguments, in: repositoryURL, environment: environment)
        } else {
            _ = try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
        }
        let savedEntry = GitSubtreeEntry(
            id: entry.id,
            name: entry.name,
            path: entry.path,
            repository: entry.repository,
            branch: entry.branch,
            squash: entry.squash,
            folderExists: true
        )
        try await registry.save(savedEntry, in: repositoryURL)
        notifySubtreeMutationSucceeded(in: repositoryURL)
        return savedEntry
    }

    func pullSubtree(
        _ entry: GitSubtreeEntry,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?
    ) async throws {
        try await rejectBlockedSubtreeOperation(in: repositoryURL)
        let injection = try await credentialInjection(
            for: entry.repository,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(),
            sshCredentialInjector: TemporaryGitSSHCredentialInjector()
        )
        defer { injection?.cleanup() }

        var arguments = [
            "subtree",
            "pull",
            "--prefix=\(entry.path)",
            entry.repository,
            entry.branch
        ]
        if entry.squash {
            arguments.append("--squash")
        }
        if let environment = gitEnvironment(for: entry.repository, injection: injection) {
            _ = try await runGit(arguments: arguments, in: repositoryURL, environment: environment)
        } else {
            _ = try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
        }
        notifySubtreeMutationSucceeded(in: repositoryURL)
    }

    func pushSubtree(
        _ entry: GitSubtreeEntry,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?
    ) async throws {
        try await rejectBlockedSubtreeOperation(in: repositoryURL)
        let injection = try await credentialInjection(
            for: entry.repository,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(),
            sshCredentialInjector: TemporaryGitSSHCredentialInjector()
        )
        defer { injection?.cleanup() }

        let pushArguments = [
            "subtree",
            "push",
            "--prefix=\(entry.path)",
            entry.repository,
            entry.branch
        ]
        if let environment = gitEnvironment(for: entry.repository, injection: injection) {
            _ = try await runGit(arguments: pushArguments, in: repositoryURL, environment: environment)
        } else {
            _ = try await runRemoteGit(arguments: pushArguments, in: repositoryURL, injection: injection)
        }
        notifySubtreeMutationSucceeded(in: repositoryURL)
    }

    func subtrees(
        in repositoryURL: URL,
        registry: any GitSubtreeRegistryProtocol = GitSubtreeRegistry()
    ) async throws -> [GitSubtreeEntry] {
        try await registry.entries(in: repositoryURL)
    }

    func linkExistingSubtree(
        _ request: SubtreeLinkRequest,
        in repositoryURL: URL,
        registry: any GitSubtreeRegistryProtocol = GitSubtreeRegistry()
    ) async throws -> GitSubtreeEntry {
        let existing = try await registry.entries(in: repositoryURL)
        let entry = try await validatedLinkedSubtreeEntry(
            request,
            existing: existing,
            in: repositoryURL
        )
        try await registry.save(entry, in: repositoryURL)
        notifySubtreeMutationSucceeded(in: repositoryURL)
        return entry
    }

    func unlinkSubtree(
        id: String,
        in repositoryURL: URL,
        registry: any GitSubtreeRegistryProtocol = GitSubtreeRegistry()
    ) async throws {
        try await registry.remove(id: id, in: repositoryURL)
        notifySubtreeMutationSucceeded(in: repositoryURL)
    }

    private func validatedLinkedSubtreeEntry(
        _ request: SubtreeLinkRequest,
        existing: [GitSubtreeEntry],
        in repositoryURL: URL
    ) async throws -> GitSubtreeEntry {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw GitSubtreeRegistryError.emptyName
        }

        let repository = try validatedSubtreeRepository(request.repository)

        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitSubtreeRegistryError.emptyBranch
        }

        let path = try GitSubtreeRegistry.normalizedRelativePath(request.path, in: repositoryURL)
        try GitSubtreeRegistry.rejectPathConflict(path, existing: existing)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent(path, isDirectory: true).path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw SubtreeLinkValidationError.missingDirectory(path)
        }

        let trackedOutput = try? await runGit(
            arguments: ["ls-files", "--error-unmatch", "--", path],
            in: repositoryURL
        )
        guard trackedOutput?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SubtreeLinkValidationError.untrackedDirectory(path)
        }

        return GitSubtreeEntry(
            id: GitSubtreeRegistry.uniqueID(for: path, existingIDs: Set(existing.map(\.id))),
            name: name,
            path: path,
            repository: repository,
            branch: branch,
            squash: request.squash,
            folderExists: true
        )
    }

    private func validatedNewSubtreeEntry(
        _ request: SubtreeLinkRequest,
        existing: [GitSubtreeEntry],
        in repositoryURL: URL
    ) throws -> GitSubtreeEntry {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw GitSubtreeRegistryError.emptyName
        }

        let repository = try validatedSubtreeRepository(request.repository)

        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitSubtreeRegistryError.emptyBranch
        }

        let path = try GitSubtreeRegistry.normalizedRelativePath(request.path, in: repositoryURL)
        try GitSubtreeRegistry.rejectPathConflict(path, existing: existing)
        try rejectExistingSubtreePrefix(path, in: repositoryURL)

        return GitSubtreeEntry(
            id: GitSubtreeRegistry.uniqueID(for: path, existingIDs: Set(existing.map(\.id))),
            name: name,
            path: path,
            repository: repository,
            branch: branch,
            squash: request.squash,
            folderExists: false
        )
    }

    /// Validates the upstream repository value. Absolute local paths must point
    /// at a Git repository (working tree or bare), mirroring the submodule flow.
    /// Remote URLs are returned trimmed without further checks.
    private func validatedSubtreeRepository(_ rawValue: String) throws -> String {
        let repository = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repository.isEmpty else {
            throw GitSubtreeRegistryError.emptyRepository
        }
        guard NSString(string: repository).isAbsolutePath else {
            return repository
        }
        let localURL = URL(fileURLWithPath: repository).standardizedFileURL
        var isDirectory: ObjCBool = false
        let hasDotGit = FileManager.default.fileExists(
            atPath: localURL.appendingPathComponent(".git").path,
            isDirectory: &isDirectory
        )
        let hasHead = FileManager.default.fileExists(
            atPath: localURL.appendingPathComponent("HEAD").path
        )
        let hasObjects = FileManager.default.fileExists(
            atPath: localURL.appendingPathComponent("objects").path,
            isDirectory: &isDirectory
        )
        guard hasDotGit || (hasHead && hasObjects) else {
            throw GitSubtreeRegistryError.invalidLocalRepository
        }
        return repository
    }

    /// `git subtree add` fails with `fatal: prefix '<path>' already exists.`
    /// even for empty folders (e.g. left behind by Unlink, which keeps files by
    /// design, or created by the folder picker). Fail fast with an actionable
    /// message instead of leaking the raw git fatal. Empty folders are allowed
    /// through and removed before git runs.
    private func rejectExistingSubtreePrefix(_ path: String, in repositoryURL: URL) throws {
        let prefixURL = repositoryURL.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: prefixURL.path, isDirectory: &isDirectory) else {
            return
        }
        guard isDirectory.boolValue else {
            throw GitSubtreeRegistryError.prefixAlreadyExists(path)
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: prefixURL,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        guard contents.isEmpty else {
            throw GitSubtreeRegistryError.prefixAlreadyExists(path)
        }
    }

    /// Removes an empty folder at the subtree prefix so `git subtree add` does
    /// not fail on it. Mirrors `removeEmptySubmoduleDestinationIfNeeded`.
    private func removeEmptySubtreePrefixIfNeeded(path: String, in repositoryURL: URL) throws {
        let prefixURL = repositoryURL.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: prefixURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }
        guard try FileManager.default.contentsOfDirectory(
            at: prefixURL,
            includingPropertiesForKeys: nil,
            options: []
        ).isEmpty else {
            return
        }
        try FileManager.default.removeItem(at: prefixURL)
    }

    /// Returns an environment allowing the `file` transport when the upstream
    /// is a local path, mirroring the submodule add flow. Returns nil when
    /// there is neither an injection nor a local path, letting the caller use
    /// the default `runRemoteGit` path.
    private func gitEnvironment(
        for repository: String,
        injection: GitCredentialInjection?
    ) -> [String: String]? {
        guard NSString(string: repository).isAbsolutePath else {
            return injection?.environment
        }
        var environment = injection?.environment ?? ProcessInfo.processInfo.environment
        environment["GIT_ALLOW_PROTOCOL"] = "file"
        return environment
    }

    private func rejectBlockedSubtreeOperation(in repositoryURL: URL) async throws {
        let decision = try await subtreeOperationDecision(in: repositoryURL)
        guard decision.isAllowed else {
            throw GitError.commandFailed(decision.message ?? SubtreeOperationPolicy.dirtyTreeMessage)
        }
    }

    private func notifySubtreeMutationSucceeded(in repositoryURL: URL) {
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }
}
