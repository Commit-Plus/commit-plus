//
//  GitStatusService+Remote.swift
//  macgit
//

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
    func fetch(
        remote: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector(),
        sshCredentialInjector: GitSSHCredentialInjecting = TemporaryGitSSHCredentialInjector()
    ) async throws {
        let injection = try await credentialInjection(
            for: remote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        defer { injection?.cleanup() }
        _ = try await runRemoteGit(arguments: ["fetch", remote], in: repositoryURL, injection: injection)
        await branchListCache.invalidateRemote(repositoryURL: repositoryURL, remote: remote)
    }

    func push(
        options: PushOptions,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector(),
        sshCredentialInjector: GitSSHCredentialInjecting = TemporaryGitSSHCredentialInjector()
    ) async throws -> String {
        let injection = try await credentialInjection(
            for: options.remote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        defer { injection?.cleanup() }

        var outputs: [String] = []
        for branch in options.branches {
            let remoteBranch = options.branchMappings[branch] ?? branch
            let refSpec = remoteBranch == branch ? branch : "\(branch):\(remoteBranch)"
            let output = try await runRemoteGit(
                arguments: ["push", options.remote, refSpec],
                in: repositoryURL,
                injection: injection
            )
            outputs.append(output)
        }
        for tag in options.tags {
            let ref = "refs/tags/\(tag)"
            var arguments = ["push", options.remote]
            if options.forceTags {
                arguments.append("--force")
            }
            arguments.append("\(ref):\(ref)")
            let output = try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
            outputs.append(output)
        }
        if options.pushTags {
            let tagOutput = try await runRemoteGit(
                arguments: ["push", options.remote, "--tags"],
                in: repositoryURL,
                injection: injection
            )
            outputs.append(tagOutput)
        }
        if !options.branches.isEmpty {
            await branchListCache.invalidateRemote(repositoryURL: repositoryURL, remote: options.remote)
        }
        return outputs.joined(separator: "\n")
    }

    func deleteRemoteTag(
        name: String,
        remote: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector(),
        sshCredentialInjector: GitSSHCredentialInjecting = TemporaryGitSSHCredentialInjector()
    ) async throws {
        let injection = try await credentialInjection(
            for: remote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        defer { injection?.cleanup() }
        _ = try await runRemoteGit(
            arguments: ["push", remote, "--delete", name],
            in: repositoryURL,
            injection: injection
        )
    }

    func pull(
        remote: String,
        branch: String,
        options: PullOptions,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector(),
        sshCredentialInjector: GitSSHCredentialInjecting = TemporaryGitSSHCredentialInjector()
    ) async throws -> String {
        var arguments = ["pull", remote, branch]
        if !options.commitMerged { arguments.append("--no-commit") }
        if !options.includeMessages { arguments.append("--no-log") }
        if options.noFastForward { arguments.append("--no-ff") }
        if options.rebaseInstead {
            arguments.append("--rebase")
        } else {
            arguments.append("--no-rebase")
        }
        let injection = try await credentialInjection(
            for: remote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        defer { injection?.cleanup() }
        return try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
    }

    func pullBranchFromUpstream(
        branch: String,
        in repositoryURL: URL,
        options: PullOptions = PullOptions(),
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async throws -> String {
        guard let upstreamRef = await upstreamBranch(for: branch, in: repositoryURL) else {
            throw GitError.commandFailed("Branch '\(branch)' does not have an upstream branch.")
        }
        guard let remoteBranch = remoteBranchRef(from: upstreamRef) else {
            throw GitError.commandFailed("Could not parse upstream branch '\(upstreamRef)'.")
        }
        return try await pull(
            remote: remoteBranch.remote,
            branch: remoteBranch.branch,
            options: options,
            in: repositoryURL,
            credentialResolver: credentialResolver
        )
    }

    func fetchAndFastForwardBranchFromUpstream(
        branch: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async throws -> String {
        guard let upstreamRef = await upstreamBranch(for: branch, in: repositoryURL) else {
            throw GitError.commandFailed("Branch '\(branch)' does not have an upstream branch.")
        }
        guard let remoteBranch = remoteBranchRef(from: upstreamRef) else {
            throw GitError.commandFailed("Could not parse upstream branch '\(upstreamRef)'.")
        }

        try await fetchBranch(
            remote: remoteBranch.remote,
            branch: remoteBranch.branch,
            in: repositoryURL,
            credentialResolver: credentialResolver
        )

        guard let localTip = await tipHash(for: branch, in: repositoryURL),
              let upstreamTip = await tipHash(for: upstreamRef, in: repositoryURL) else {
            throw GitError.commandFailed("Could not resolve branch '\(branch)' or upstream '\(upstreamRef)'.")
        }

        guard localTip != upstreamTip else {
            return "Already up to date."
        }

        guard await isAncestor(localTip, of: upstreamTip, in: repositoryURL) else {
            throw GitError.commandFailed("Branch '\(branch)' has diverged from '\(upstreamRef)'. Pull or rebase it manually.")
        }

        if await currentBranch(in: repositoryURL) == branch {
            return try await runGit(arguments: ["merge", "--ff-only", upstreamRef], in: repositoryURL)
        }

        return try await runGit(arguments: ["branch", "--force", branch, upstreamRef], in: repositoryURL)
    }

    func fetch(
        options: FetchOptions,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector(),
        sshCredentialInjector: GitSSHCredentialInjecting = TemporaryGitSSHCredentialInjector()
    ) async throws {
        if options.fetchAllRemotes {
            let remoteNames = await remotes(in: repositoryURL)
            for remote in remoteNames {
                var arguments = ["fetch", remote]
                if options.prune {
                    arguments.append("--prune")
                }
                if options.fetchTags {
                    arguments.append("--tags")
                }
                do {
                    let injection = try await credentialInjection(
                        for: remote,
                        in: repositoryURL,
                        credentialResolver: credentialResolver,
                        credentialInjector: credentialInjector,
                        sshCredentialInjector: sshCredentialInjector
                    )
                    defer { injection?.cleanup() }
                    _ = try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
                }
            }
            await branchListCache.invalidateRemotes(repositoryURL: repositoryURL)
            return
        }

        var arguments = ["fetch"]
        if options.prune {
            arguments.append("--prune")
        }
        if options.fetchTags {
            arguments.append("--tags")
        }
        let injection = try await credentialInjectionForFetch(
            options: options,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        defer { injection?.cleanup() }
        _ = try await runRemoteGit(arguments: arguments, in: repositoryURL, injection: injection)
        await branchListCache.invalidateRemotes(repositoryURL: repositoryURL)
    }

    func fetchBranch(
        remote: String,
        branch: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector(),
        sshCredentialInjector: GitSSHCredentialInjecting = TemporaryGitSSHCredentialInjector()
    ) async throws {
        let injection = try await credentialInjection(
            for: remote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        defer { injection?.cleanup() }
        let remoteTrackingRef = "refs/remotes/\(remote)/\(branch)"
        let branchRefSpec = "+refs/heads/\(branch):\(remoteTrackingRef)"
        _ = try await runRemoteGit(arguments: ["fetch", remote, branchRefSpec], in: repositoryURL, injection: injection)
        await branchListCache.invalidateRemote(repositoryURL: repositoryURL, remote: remote)
    }

    private func isAncestor(_ ancestor: String, of descendant: String, in repositoryURL: URL) async -> Bool {
        do {
            _ = try await runGit(arguments: ["merge-base", "--is-ancestor", ancestor, descendant], in: repositoryURL)
            return true
        } catch {
            return false
        }
    }

    func fetchPullRequestRef(
        remote: String,
        reference: String,
        localBranch: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        credentialInjector: GitCredentialInjecting = TemporaryGitCredentialInjector(),
        sshCredentialInjector: GitSSHCredentialInjecting = TemporaryGitSSHCredentialInjector()
    ) async throws {
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocalBranch = localBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty, !trimmedReference.isEmpty, !trimmedLocalBranch.isEmpty else {
            throw GitError.commandFailed("Pull request fetch reference is required.")
        }

        let injection = try await credentialInjection(
            for: trimmedRemote,
            in: repositoryURL,
            credentialResolver: credentialResolver,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        defer { injection?.cleanup() }

        let refspec = "\(trimmedReference):refs/heads/\(trimmedLocalBranch)"
        _ = try await runRemoteGit(arguments: ["fetch", trimmedRemote, refspec], in: repositoryURL, injection: injection)
    }

    @discardableResult
    func checkoutRemoteBranch(remote: String, branch: String, in repositoryURL: URL) async throws -> String {
        try await checkoutRemoteBranch(
            remote: remote,
            branch: branch,
            localBranch: branch,
            trackRemote: true,
            in: repositoryURL
        )
    }

    @discardableResult
    func checkoutRemoteBranch(
        remote: String,
        branch: String,
        localBranch: String,
        trackRemote: Bool,
        in repositoryURL: URL
    ) async throws -> String {
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocalBranch = localBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemote.isEmpty, !trimmedBranch.isEmpty, !trimmedLocalBranch.isEmpty else {
            throw GitError.commandFailed("Remote branch is required.")
        }
        guard trimmedBranch != "HEAD" else {
            throw GitError.commandFailed("Cannot checkout a remote HEAD symbolic ref.")
        }

        let localBranches = await cachedLocalBranches(in: repositoryURL)
        if localBranches.contains(trimmedLocalBranch) {
            _ = try await runGit(arguments: ["checkout", trimmedLocalBranch], in: repositoryURL)
            return trimmedLocalBranch
        }

        var arguments = ["checkout", "-b", trimmedLocalBranch]
        if trackRemote {
            arguments.append(contentsOf: ["--track", "\(trimmedRemote)/\(trimmedBranch)"])
        } else {
            arguments.append("\(trimmedRemote)/\(trimmedBranch)")
        }
        _ = try await runGit(arguments: arguments, in: repositoryURL)
        return trimmedLocalBranch
    }

    func remotes(in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["remote"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    func remoteBranches(remote: String, in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["branch", "-r", "--list", "\(remote)/*"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Remove leading "* " if present
            let clean = trimmed.hasPrefix("* ") ? String(trimmed.dropFirst(2)) : trimmed
            // Symbolic refs such as origin/HEAD -> origin/main are aliases, not branches.
            guard !clean.contains(" -> ") else { return nil }
            // Return just the branch name without remote prefix
            let prefix = "\(remote)/"
            if clean.hasPrefix(prefix) {
                return String(clean.dropFirst(prefix.count))
            }
            return clean
        }.filter { !$0.isEmpty }
    }

    func cachedRemoteBranches(remote: String, in repositoryURL: URL) async -> [String] {
        await branchListCache.values(for: .remote(repositoryURL, remote)) { [repositoryURL, remote] in
            await self.remoteBranches(remote: remote, in: repositoryURL)
        }
    }

    func remoteURL(remote: String, in repositoryURL: URL) async -> String {
        let url = (try? await runGit(arguments: ["remote", "get-url", remote], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return url
    }

    func remoteURLs(in repositoryURL: URL) async -> [String] {
        let names = await remotes(in: repositoryURL)
        var urls: [String] = []
        for name in names {
            let url = await remoteURL(remote: name, in: repositoryURL)
            if !url.isEmpty { urls.append(url) }
        }
        return urls
    }

    func defaultBranch(in repositoryURL: URL, remote: String) async -> String? {
        let output = try? await runGit(
            arguments: ["symbolic-ref", "--quiet", "--short", "refs/remotes/\(remote)/HEAD"],
            in: repositoryURL
        )
        let branch = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch?.isEmpty == false ? branch : nil
    }

    func addRemote(name: String, url: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["remote", "add", name, url], in: repositoryURL)
    }

    func removeRemote(name: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["remote", "remove", name], in: repositoryURL)
    }

    func setRemoteURL(name: String, url: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["remote", "set-url", name, url], in: repositoryURL)
    }

    private func remoteBranchRef(from upstreamRef: String) -> (remote: String, branch: String)? {
        let parts = upstreamRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (remote: String(parts[0]), branch: String(parts[1]))
    }

    private func credentialInjectionForFetch(
        options: FetchOptions,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?,
        credentialInjector: GitCredentialInjecting,
        sshCredentialInjector: GitSSHCredentialInjecting
    ) async throws -> GitCredentialInjection? {
        guard let credentialResolver else { return nil }
        let remoteNames = await remotes(in: repositoryURL)
        let credentials = try await remoteNames.asyncCompactMap { remote -> RemoteGitCredential? in
            let remoteURLString = await remoteURL(remote: remote, in: repositoryURL)
            return try remoteCredential(for: remoteURLString, credentialResolver: credentialResolver)
        }
        let uniqueCredentials = credentials.reduce(into: [RemoteGitCredential]()) { result, credential in
            if !result.contains(credential) {
                result.append(credential)
            }
        }
        guard let credential = uniqueCredentials.first else { return nil }
        guard uniqueCredentials.count == 1 else {
            throw GitProviderCredentialError.multipleMatchingAccounts(host: "configured remotes")
        }
        return try injection(
            for: credential,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
    }

}

private extension Sequence {
    func asyncCompactMap<Element>(
        _ transform: (Self.Element) async throws -> Element?
    ) async throws -> [Element] {
        var values: [Element] = []
        for element in self {
            if let value = try await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}
