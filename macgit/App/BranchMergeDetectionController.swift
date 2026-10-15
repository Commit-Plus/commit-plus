// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

@MainActor
final class BranchMergeDetectionController: ObservableObject {
    @Published private(set) var assessments: [String: BranchMergeAssessment] = [:]
    @Published private(set) var loadingBranches: Set<String> = []

    private weak var providerAccountController: GitProviderAccountController?
    private let tokenVault: GitProviderTokenVault
    private let services: [GitProviderKind: any BranchMergeEvidenceProviding]
    private let hintStore: BranchMergeHintStore
    private var cache: [CacheKey: BranchMergeAssessment] = [:]
    private var generation = UUID()
    private var accountObservation: AnyCancellable?
    private let cacheTTL: TimeInterval = 15 * 60

    init(
        providerAccountController: GitProviderAccountController? = nil,
        tokenVault: GitProviderTokenVault? = nil,
        services: [GitProviderKind: any BranchMergeEvidenceProviding]? = nil,
        hintStore: BranchMergeHintStore? = nil
    ) {
        self.providerAccountController = providerAccountController
        self.tokenVault = tokenVault ?? KeychainGitProviderTokenVault()
        self.services = services ?? [
            .github: GitHubBranchMergeEvidenceService(),
            .gitlab: GitLabBranchMergeEvidenceService(),
        ]
        self.hintStore = hintStore ?? BranchMergeHintStore()
        accountObservation = providerAccountController?.$accounts.dropFirst().sink { [weak self] _ in self?.invalidate() }
    }

    func assessment(for branch: String, repositoryURL: URL) -> BranchMergeAssessment? {
        guard !hintStore.isSuppressed(repositoryURL: repositoryURL, branch: branch) else { return nil }
        return assessments[branch]
    }

    func isHintSuppressed(for branch: String, repositoryURL: URL) -> Bool {
        hintStore.isSuppressed(repositoryURL: repositoryURL, branch: branch)
    }

    func setHintSuppressed(_ suppressed: Bool, for branch: String, repositoryURL: URL) {
        hintStore.setSuppressed(suppressed, repositoryURL: repositoryURL, branch: branch)
        objectWillChange.send()
    }

    func invalidate() {
        generation = UUID()
        cache.removeAll()
        assessments.removeAll()
        loadingBranches.removeAll()
    }

    func refresh(
        branches: [String],
        repositoryURL: URL,
        entitlement: AccountEntitlement,
        policy: FeatureAccessPolicy,
        force: Bool = false
    ) async {
        guard FeatureAccessResolver(policy: policy).decision(
            for: .branchMergeDetection,
            entitlement: entitlement
        ).isAllowed else {
            invalidate()
            return
        }
        let currentGeneration = generation
        loadingBranches.formUnion(branches)
        await withTaskGroup(of: BranchMergeAssessment?.self) { group in
            for branch in branches {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.detect(
                        branch: branch,
                        repositoryURL: repositoryURL,
                        force: force
                    )
                }
            }
            for await assessment in group {
                guard generation == currentGeneration, let assessment else { continue }
                assessments[assessment.branch] = assessment
                loadingBranches.remove(assessment.branch)
            }
        }
        guard generation == currentGeneration else { return }
        loadingBranches.subtract(branches)
    }

    func revalidateFullyMerged(
        branch: String,
        repositoryURL: URL,
        entitlement: AccountEntitlement,
        policy: FeatureAccessPolicy
    ) async -> BranchMergeAssessment? {
        guard FeatureAccessResolver(policy: policy).decision(
            for: .branchMergeDetection,
            entitlement: entitlement
        ).isAllowed else { return nil }
        guard await isCleanupAllowed(branch: branch, repositoryURL: repositoryURL) else { return nil }
        let result = await detect(branch: branch, repositoryURL: repositoryURL, force: true)
        if let result { assessments[branch] = result }
        return result?.isFullyMerged == true ? result : nil
    }

    private func detect(branch: String, repositoryURL: URL, force: Bool) async -> BranchMergeAssessment? {
        guard let tip = await GitStatusService.shared.tipHash(for: branch, in: repositoryURL) else { return nil }
        let key = CacheKey(repository: repositoryURL.standardizedFileURL.path, branch: branch, tip: tip)
        if !force, let cached = cache[key], Date.now.timeIntervalSince(cached.checkedAt) < cacheTTL {
            return cached
        }

        let accounts = providerAccountController?.accounts ?? []
        let knownHosts = accounts.map { GitProviderHost(kind: $0.provider, baseURL: $0.hostURL) }
        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        let remoteURLs = await withTaskGroup(of: (String, String).self, returning: [(String, String)].self) { group in
            for remote in remotes {
                group.addTask {
                    let value = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
                    return (remote, value)
                }
            }
            var values: [(String, String)] = []
            for await value in group { values.append(value) }
            return values
        }
        let knownGitLabHosts = Set(accounts.filter { $0.provider == .gitlab }.compactMap { $0.hostURL.host?.lowercased() })
        let remoteContexts = remoteURLs.compactMap { remote, value -> RemoteContext? in
            guard !value.isEmpty, let identity = GitRemoteIdentityResolver.identity(
                from: value,
                knownGitLabHosts: knownGitLabHosts,
                knownHosts: knownHosts
            ) else { return nil }
            return RemoteContext(name: remote, identity: identity)
        }
        let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL)
        let sourceRemoteName = upstream?.split(separator: "/", maxSplits: 1).first.map(String.init)
        let sourceContext = remoteContexts.first { $0.name == sourceRemoteName }
            ?? remoteContexts.first { $0.name == "origin" }
            ?? remoteContexts.first
        guard let sourceContext else {
            return publish(.init(branch: branch, tipSHA: tip, state: .unknown, evidence: [],
                                 detail: "No supported GitHub or GitLab remote could be resolved.", checkedAt: .now), key: key)
        }

        for context in remoteContexts {
            if let defaultRef = await GitStatusService.shared.defaultBranch(in: repositoryURL, remote: context.name),
               await GitStatusService.shared.branchTipIsAncestor(tip, of: defaultRef, in: repositoryURL) {
                return publish(.init(
                    branch: branch,
                    tipSHA: tip,
                    state: .fullyMerged,
                    evidence: [.init(kind: .gitAncestry, title: "Contained in \(defaultRef)", webURL: nil,
                                     targetBranch: String(defaultRef.split(separator: "/", maxSplits: 1).last ?? ""), mergedAt: nil)],
                    detail: "The current branch tip is an ancestor of the remote default branch.",
                    checkedAt: .now
                ), key: key)
            }
        }

        guard let service = services[sourceContext.identity.provider] else {
            // TODO: Add Bitbucket and Azure DevOps adapters here without changing the classifier or sidebar contract.
            return publish(.init(branch: branch, tipSHA: tip, state: .unknown, evidence: [],
                                 detail: "Merge detection is not implemented for this provider yet.", checkedAt: .now), key: key)
        }
        guard let account = matchingAccount(for: sourceContext.identity, accounts: accounts),
              let token = try? tokenVault.readToken(for: account) else {
            return publish(.init(branch: branch, tipSHA: tip, state: .unknown, evidence: [],
                                 detail: "Connect or reconnect the matching provider account to check merged pull requests.", checkedAt: .now), key: key)
        }

        var didCompleteProviderRequest = false
        for target in remoteContexts where target.identity.provider == sourceContext.identity.provider {
            let targetRepository = target.identity.repositoryIdentity
            do {
                let changes = try await service.mergedChanges(
                    targetRepository: targetRepository,
                    sourceRepository: sourceContext.identity.repositoryIdentity,
                    sourceBranch: branch,
                    token: token
                )
                didCompleteProviderRequest = true
                if let matched = changes.first(where: { $0.sourceSHA.caseInsensitiveCompare(tip) == .orderedSame }) {
                    return publish(.init(
                        branch: branch,
                        tipSHA: tip,
                        state: .fullyMerged,
                        evidence: [.init(kind: .pullRequest, title: "#\(matched.number) \(matched.title)",
                                         webURL: matched.webURL, targetBranch: matched.targetBranch, mergedAt: matched.mergedAt)],
                        detail: "The merged pull request covers the current branch tip.",
                        checkedAt: .now
                    ), key: key)
                }
            } catch {
                continue
            }
        }
        let result = BranchMergeAssessment(
            branch: branch,
            tipSHA: tip,
            state: didCompleteProviderRequest ? .notFullyMerged : .unknown,
            evidence: [],
            detail: didCompleteProviderRequest
                ? "No merged pull request covers the current branch tip."
                : "The provider merge status is currently unavailable.",
            checkedAt: .now
        )
        return publish(result, key: key)
    }

    private func matchingAccount(for identity: GitRemoteIdentity, accounts: [GitProviderAccount]) -> GitProviderAccount? {
        accounts.first {
            $0.provider == identity.provider
                && $0.tokenStatus == .valid
                && GitProviderHost.identityKey($0.hostURL) == GitProviderHost.identityKey(identity.hostURL)
        }
    }

    private func isCleanupAllowed(branch: String, repositoryURL: URL) async -> Bool {
        let current = await GitStatusService.shared.currentBranch(in: repositoryURL)
        guard current != branch else { return false }
        let worktreePath = try? await GitStatusService.shared.worktreePath(for: branch, in: repositoryURL)
        guard worktreePath == nil else { return false }

        let accounts = providerAccountController?.accounts ?? []
        let knownHosts = accounts.map { GitProviderHost(kind: $0.provider, baseURL: $0.hostURL) }
        let knownGitLabHosts = Set(accounts.filter { $0.provider == .gitlab }.compactMap { $0.hostURL.host?.lowercased() })
        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL)
        let preferredRemote = upstream?.split(separator: "/", maxSplits: 1).first.map(String.init)
            ?? remotes.first(where: { $0 == "origin" }) ?? remotes.first

        for remote in remotes {
            if let defaultRef = await GitStatusService.shared.defaultBranch(in: repositoryURL, remote: remote),
               String(defaultRef.split(separator: "/", maxSplits: 1).last ?? "") == branch {
                return false
            }
        }
        guard let preferredRemote else { return false }
        let remoteURL = await GitStatusService.shared.remoteURL(remote: preferredRemote, in: repositoryURL)
        guard let identity = GitRemoteIdentityResolver.identity(
            from: remoteURL,
            knownGitLabHosts: knownGitLabHosts,
            knownHosts: knownHosts
        ), [.github, .gitlab].contains(identity.provider),
              let account = matchingAccount(for: identity, accounts: accounts),
              let token = try? tokenVault.readToken(for: account) else { return false }
        return await BranchProtectionService().status(branch: branch, identity: identity, token: token) == .unprotected
    }

    private func publish(_ assessment: BranchMergeAssessment, key: CacheKey) -> BranchMergeAssessment {
        cache = cache.filter { $0.key.repository != key.repository || $0.key.branch != key.branch }
        cache[key] = assessment
        return assessment
    }

    private struct CacheKey: Hashable { let repository: String; let branch: String; let tip: String }
    private struct RemoteContext: Sendable { let name: String; let identity: GitRemoteIdentity }
}

private extension GitRemoteIdentity {
    var repositoryIdentity: GitRepositoryIdentity {
        GitRepositoryIdentity(provider: provider, hostURL: hostURL, owner: ownerPath, name: repositoryName)
    }
}

