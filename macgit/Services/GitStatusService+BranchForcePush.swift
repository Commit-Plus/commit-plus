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
    /// A force push must address one endpoint, with the same identity used for credentials.
    private func forcePushURL(remote: String, in repositoryURL: URL) async throws -> String {
        guard !remote.isEmpty, !remote.hasPrefix("-"),
              await remotes(in: repositoryURL).contains(remote) else {
            throw GitError.commandFailed("The selected remote is no longer configured.")
        }
        let pushURLs = try await runGit(arguments: ["remote", "get-url", "--push", "--all", remote], in: repositoryURL)
            .split(whereSeparator: \.isNewline).map(String.init)
        let fetchURL = try await runGit(arguments: ["remote", "get-url", remote], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard pushURLs.count == 1, pushURLs[0] == fetchURL else {
            throw GitError.commandFailed("Force Push requires one matching fetch and push URL. Configure a separate remote for this destination.")
        }
        return fetchURL
    }

    func prepareBranchForcePush(
        remote: String,
        localBranch: String,
        remoteBranch: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async throws -> BranchForcePushPlan {
        _ = try await runGit(arguments: ["check-ref-format", "refs/heads/\(localBranch)"], in: repositoryURL)
        _ = try await runGit(arguments: ["check-ref-format", "refs/heads/\(remoteBranch)"], in: repositoryURL)
        let endpoint = try await forcePushURL(remote: remote, in: repositoryURL)
        let injection = try await credentialInjection(
            for: remote, in: repositoryURL, credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(),
            sshCredentialInjector: TemporaryGitSSHCredentialInjector()
        )
        let cleanup = await injection?.cleanup
        defer { cleanup?() }
        guard try await forcePushURL(remote: remote, in: repositoryURL) == endpoint else {
            throw GitError.commandFailed("Remote configuration changed. Open Force Push again.")
        }

        let id = UUID()
        let backupPrefix = "refs/commitplus/force-push/\(id.uuidString)"
        // Fetch only the selected branch; preserve the reviewed remote commit for recovery.
        _ = try await runRemoteGit(
            arguments: ["fetch", "--no-tags", "--no-write-fetch-head", "--", endpoint,
                        "refs/heads/\(remoteBranch):\(backupPrefix)/remote"],
            in: repositoryURL, injection: injection
        )
        let remoteHash = try await forcePushCommit(backupPrefix + "/remote", in: repositoryURL)
        let localHash = try await forcePushCommit("refs/heads/\(localBranch)", in: repositoryURL)
        let countOutput = try await runGit(arguments: ["rev-list", "--count", "\(localHash)..\(remoteHash)"], in: repositoryURL)
        guard let count = Int(countOutput.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 else {
            throw GitError.commandFailed("This branch does not need Force Push. Use Push for a normal update.")
        }
        _ = try await runGit(arguments: ["update-ref", backupPrefix + "/local", localHash], in: repositoryURL)
        let remoteHead = try? await runRemoteGit(
            arguments: ["ls-remote", "--symref", "--", endpoint, "HEAD"],
            in: repositoryURL, injection: injection
        )
        return BranchForcePushPlan(
            id: id, remote: remote, remoteURL: endpoint,
            localBranch: localBranch, remoteBranch: remoteBranch,
            localHash: localHash, remoteHash: remoteHash,
            removedCommitCount: count,
            isDefaultBranch: remoteHead?.contains("ref: refs/heads/\(remoteBranch)\tHEAD") == true
                || ["main", "master"].contains(remoteBranch)
        )
    }

    func forcePushBranch(
        _ plan: BranchForcePushPlan,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async throws {
        try await replaceRemoteBranch(
            plan, restoring: false, requireLocalTip: true,
            in: repositoryURL, credentialResolver: credentialResolver
        )
    }

    /// Undo and redo use the same explicit lease and immutable commits as the original action.
    func replaceRemoteBranch(
        _ plan: BranchForcePushPlan,
        restoring: Bool,
        requireLocalTip: Bool = false,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async throws {
        let injection = try await credentialInjection(
            for: plan.remote, in: repositoryURL, credentialResolver: credentialResolver,
            credentialInjector: TemporaryGitCredentialInjector(),
            sshCredentialInjector: TemporaryGitSSHCredentialInjector()
        )
        let cleanup = await injection?.cleanup
        defer { cleanup?() }
        guard try await forcePushURL(remote: plan.remote, in: repositoryURL) == plan.remoteURL else {
            throw GitError.commandFailed("Remote configuration changed. Open Force Push again.")
        }
        if requireLocalTip {
            guard try await forcePushCommit("refs/heads/\(plan.localBranch)", in: repositoryURL) == plan.localHash else {
                throw GitError.commandFailed("The local branch changed. Open Force Push again to review it.")
            }
        }
        let expected = restoring ? plan.localHash : plan.remoteHash
        let target = restoring ? plan.remoteHash : plan.localHash
        // `--force-with-lease` is skipped by Git when the push is a no-op, so
        // verify the reviewed remote tip explicitly before replacing anything.
        let currentRemoteTip = try await remoteBranchTip(
            plan.remoteBranch, at: plan.remoteURL, in: repositoryURL, injection: injection
        )
        guard currentRemoteTip == expected else {
            throw GitError.commandFailed(
                "The remote branch changed since Force Push was reviewed. Review it again before replacing it."
            )
        }
        _ = try await forcePushCommit(target, in: repositoryURL)
        do {
            // A URL and one full refspec avoid remote.push/mirror config expanding the scope.
            _ = try await runRemoteGit(
                arguments: ["-c", "push.followTags=false", "push", "--no-follow-tags",
                            "--recurse-submodules=no",
                            "--force-with-lease=refs/heads/\(plan.remoteBranch):\(expected)",
                            "--", plan.remoteURL, "\(target):refs/heads/\(plan.remoteBranch)"],
                in: repositoryURL, injection: injection
            )
        } catch {
            throw GitError.commandFailed(error.localizedDescription
                + "\n\nForce Push was not retried. If the remote changed, review it again before replacing it.")
        }
        await branchListCache.invalidateRemote(repositoryURL: repositoryURL, remote: plan.remote)
        // Fetching updates the sidebar's remote-tracking ref; failure must not hide a successful push.
        try? await fetchBranch(remote: plan.remote, branch: plan.remoteBranch, in: repositoryURL,
                               credentialResolver: credentialResolver)
    }

    private func forcePushCommit(_ ref: String, in repositoryURL: URL) async throws -> String {
        try await runGit(arguments: ["rev-parse", "--verify", "\(ref)^{commit}"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func remoteBranchTip(
        _ branch: String,
        at url: String,
        in repositoryURL: URL,
        injection: GitCredentialInjection?
    ) async throws -> String? {
        let output = try await runRemoteGit(
            arguments: ["ls-remote", "--heads", "--", url, "refs/heads/\(branch)"],
            in: repositoryURL, injection: injection
        )
        return output.split(whereSeparator: \.isNewline).first?
            .split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
