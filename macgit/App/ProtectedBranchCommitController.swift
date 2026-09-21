// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Combine

@MainActor
final class ProtectedBranchCommitController: ObservableObject {
    struct Warning: Identifiable {
        let id = UUID()
        let branch: String
        let remoteBranch: String
        let status: BranchProtectionService.Status
    }

    enum Decision {
        case cancel
        case commitAnyway
        case newBranch(String)
    }

    @Published var warning: Warning?
    private var continuation: CheckedContinuation<Decision, Never>?
    private var isChecking = false

    func authorize(
        repositoryURL: URL,
        settings: RepoSettings,
        credentials: GitProviderCredentialResolver,
        syncState: SyncState,
        undoManager: GitUndoManager?
    ) async -> Bool {
        guard !isChecking else { return false }
        isChecking = true
        defer { isChecking = false }
        guard !settings.skipProtectedBranchCommitWarnings else { return true }
        let git = GitStatusService.shared
        guard let branch = await git.currentBranch(in: repositoryURL), !branch.isEmpty else { return true }
        let oldHead = await git.tipHash(for: "HEAD", in: repositoryURL)
        let remotes = await git.remotes(in: repositoryURL)
        guard !remotes.isEmpty else { return true }
        let upstream = await git.upstreamBranch(for: branch, in: repositoryURL)
        let target = Self.target(branch: branch, upstream: upstream, remotes: remotes, preferredRemote: settings.defaultRemoteName)
        guard let target else { return true }
        let remoteURL = await git.remoteURL(remote: target.remote, in: repositoryURL)
        guard let identity = credentials.remoteIdentity(for: remoteURL) else { return true }
        // API credentials also apply to SSH remotes; never send SSH keys to a provider API.
        let matching = credentials.accounts.filter {
            $0.provider == identity.provider && $0.hostURL.host()?.lowercased() == identity.hostURL.host()?.lowercased()
                && ($0.transportProtocol == .https || !$0.scopes.isEmpty)
        }
        let preferenceKey = GitProviderAccountPreferenceKey.make(for: identity)
        let preferredID = credentials.preferredAccountIDsByRemoteIdentity[preferenceKey]
        let account = matching.first { $0.id == preferredID } ?? (matching.count == 1 ? matching.first : nil)
        let token = account.flatMap { try? credentials.tokenVault.readToken(for: $0) }
        let status = await BranchProtectionService().status(branch: target.branch, identity: identity, token: token)
        guard await git.currentBranch(in: repositoryURL) == branch,
              await git.tipHash(for: "HEAD", in: repositoryURL) == oldHead else {
            syncState.showInfo("The current branch changed. Review your changes and commit again.")
            return false
        }
        guard status == .protected || status == .unavailable else { return true }
        let decision = await withCheckedContinuation { continuation in
            self.continuation = continuation
            warning = Warning(branch: branch, remoteBranch: "\(target.remote)/\(target.branch)", status: status)
        }
        guard case .cancel = decision else {
            guard await git.currentBranch(in: repositoryURL) == branch,
                  await git.tipHash(for: "HEAD", in: repositoryURL) == oldHead else {
                syncState.showInfo("The current branch changed. Review your changes and commit again.")
                return false
            }
            if case .newBranch(let name) = decision {
                guard await git.isValidBranchName(name, in: repositoryURL) else {
                    syncState.showError("Enter a valid new branch name and try committing again.")
                    return false
                }
                do {
                    _ = try await git.createBranch(name: name, checkout: true, commit: nil, in: repositoryURL)
                    if let oldHead {
                        undoManager?.register(GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Create branch \(name)",
                            undoOperation: .deleteLocalBranch(name: name, force: true, expectedTip: oldHead),
                            redoOperation: .createLocalBranch(name: name, startPoint: oldHead, checkout: true)
                        ))
                    }
                    await syncState.refresh(repositoryURL: repositoryURL)
                    NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
                } catch {
                    syncState.showError(error.localizedDescription)
                    return false
                }
            }
            return true
        }
        return false
    }

    func finish(_ decision: Decision) {
        let pending = continuation
        continuation = nil
        warning = nil
        pending?.resume(returning: decision)
    }

    static func target(branch: String, upstream: String?, remotes: [String], preferredRemote: String?) -> (remote: String, branch: String)? {
        if let upstream, let remote = remotes.sorted(by: { $0.count > $1.count }).first(where: { upstream.hasPrefix($0 + "/") }) {
            return (remote, String(upstream.dropFirst(remote.count + 1)))
        }
        let remote = preferredRemote.flatMap { remotes.contains($0) ? $0 : nil }
            ?? (remotes.contains("origin") ? "origin" : remotes.first)
        return remote.map { ($0, branch) }
    }
}
