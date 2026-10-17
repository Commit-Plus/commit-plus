// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

@MainActor
final class BranchMergeDetectionController: ObservableObject {
    @Published private(set) var assessments: [String: BranchMergeAssessment] = [:]
    @Published private(set) var loadingBranches: Set<String> = []
    @Published private(set) var hintRevision = 0
    @Published private(set) var accountRevision = 0
    private var requestIDs: [String: UUID] = [:]
    private var contextTask: Task<[RemoteContext], Never>?
    private var jobs: [String: Task<Void, Never>] = [:]
    private var jobFingerprints: [String: String] = [:]
    private var queue: [(String, UUID, @MainActor () async -> Void)] = []
    private var activeJobs = 0
    private let diskCache = PullRequestDiskCache.shared

    private weak var providerAccountController: GitProviderAccountController?
    private let tokenVault: GitProviderTokenVault
    private let services: [GitProviderKind: any BranchMergeEvidenceProviding]
    private let hintStore: BranchMergeHintStore
    private var cache: [CacheKey: BranchMergeAssessment] = [:]
    private var generation = UUID()
    private var accountObservation: AnyCancellable?
    private let cacheTTL: TimeInterval = 5 * 60

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
        accountObservation = providerAccountController?.$accounts.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.invalidate()
            self?.accountRevision += 1
        }
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
        hintRevision += 1
    }

    func invalidate() {
        generation = UUID()
        requestIDs.removeAll()
        for job in jobs.values { job.cancel() }
        jobs.removeAll()
        jobFingerprints.removeAll()
        queue.removeAll()
        contextTask?.cancel()
        contextTask = nil
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
        let contexts = await remoteContexts(repositoryURL: repositoryURL)
        guard generation == currentGeneration, !Task.isCancelled else { return }
        // One ref snapshot for the repository, rather than one subprocess per branch.
        let output = try? await GitStatusService.shared.runGit(
            arguments: ["for-each-ref", "--format=%(refname:short)%09%(objectname)%09%(upstream:short)", "refs/heads/"],
            in: repositoryURL
        )
        guard generation == currentGeneration, let output else { return }
        var refs: [String: (String, String)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.count == 3 { refs[fields[0]] = (fields[1], fields[2]) }
        }
        for removed in Set(assessments.keys).subtracting(refs.keys) { assessments.removeValue(forKey: removed) }
        let context = contexts.map { "\($0.name)|\($0.identity.canonicalHTTPSURL)" }.joined(separator: "\n")
        for branch in Set(branches).sorted() {
            guard let (tip, upstream) = refs[branch] else { continue }
            let fingerprint = "\(repositoryURL.path)|\(tip)|\(upstream)|\(context)"
            if !force, jobFingerprints[branch] == fingerprint, requestIDs[branch] != nil { continue }
            if !force, jobFingerprints[branch] == fingerprint, let result = assessments[branch],
               result.isFullyMerged || Date.now.timeIntervalSince(result.checkedAt) < cacheTTL {
                continue
            }
            jobs[branch]?.cancel()
            queue.removeAll { $0.0 == branch }
            let id = UUID()
            requestIDs[branch] = id
            jobFingerprints[branch] = fingerprint
            loadingBranches.insert(branch)
            if assessments[branch]?.tipSHA != tip { assessments.removeValue(forKey: branch) }
            queue.append((branch, id, { [weak self] in
                guard let self else { return }
                let result = await detect(branch: branch, repositoryURL: repositoryURL, force: force,
                                          contexts: contexts, requestID: id)
                guard generation == currentGeneration, requestIDs[branch] == id else { return }
                if let result { updateAssessment(result) }
                loadingBranches.remove(branch)
            }))
        }
        startQueuedJobs()
    }

    private func startQueuedJobs() {
        while activeJobs < 3, !queue.isEmpty {
            let (branch, id, operation) = queue.removeFirst()
            guard requestIDs[branch] == id else { continue }
            activeJobs += 1
            jobs[branch] = Task { [weak self] in
                await operation()
                guard let self else { return }
                activeJobs -= 1
                if requestIDs[branch] == id {
                    requestIDs.removeValue(forKey: branch)
                    jobs.removeValue(forKey: branch)
                }
                startQueuedJobs()
            }
        }
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
        if let result { updateAssessment(result) }
        return result?.isFullyMerged == true ? result : nil
    }

    private func detect(branch: String, repositoryURL: URL, force: Bool, contexts: [RemoteContext]? = nil, requestID: UUID? = nil) async -> BranchMergeAssessment? {
        guard let tip = await GitStatusService.shared.tipHash(for: branch, in: repositoryURL) else { return nil }
        let remoteContexts: [RemoteContext]
        if let contexts { remoteContexts = contexts } else { remoteContexts = await self.remoteContexts(repositoryURL: repositoryURL) }
        let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL)
        guard !Task.isCancelled, requestID == nil || requestIDs[branch] == requestID else { return nil }
        let accountContext = (providerAccountController?.accounts ?? []).map { "\($0.macgitUID)|\($0.id)|\($0.tokenStatus)" }.sorted().joined(separator: "\n")
        // A merged branch tip stays merged when the target branch advances. Keep
        // provider cache identity independent from the remote default tip so an
        // automatic fetch cannot turn app activation into another API request.
        let fingerprint = remoteContexts.map { "\($0.name)|\($0.identity.canonicalHTTPSURL)" }.joined(separator: "\n") + "\n" + (upstream ?? "") + "\n" + accountContext
        let key = CacheKey(repository: repositoryURL.standardizedFileURL.path, branch: branch, tip: tip, context: fingerprint)
        let diskGeneration = await diskCache.generation()
        if !force, let saved = await diskCache.entry(BranchMergeAssessment.self, key: key.diskKey, generation: diskGeneration),
           saved.value.isFullyMerged {
            guard !Task.isCancelled, requestID == nil || requestIDs[branch] == requestID else { return nil }
            cache[key] = saved.value
            return saved.value
        }
        if !force, let cached = cache[key],
           cached.isFullyMerged || Date.now.timeIntervalSince(cached.checkedAt) < cacheTTL {
            return cached
        }

        let accounts = providerAccountController?.accounts ?? []
        let sourceRemoteName = upstream?.split(separator: "/", maxSplits: 1).first.map(String.init)
        let sourceBranch = upstream.flatMap { value -> String? in
            let parts = value.split(separator: "/", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : nil
        } ?? branch
        let epoch = generation
        let result = await detectResolved(branch: branch, tip: tip, key: key, remoteContexts: remoteContexts, accounts: accounts, sourceRemoteName: sourceRemoteName, sourceBranch: sourceBranch)
        guard !Task.isCancelled, generation == epoch,
              requestID == nil || requestIDs[branch] == requestID,
              await GitStatusService.shared.tipHash(for: branch, in: repositoryURL) == tip else { return nil }
        cache = cache.filter { $0.key.repository != key.repository || $0.key.branch != branch }
        cache[key] = result
        if result.isFullyMerged {
            await diskCache.save(result, key: key.diskKey, accountID: "branch-merge", kind: "branch-merge-v1",
                                 ttl: 365 * 24 * 60 * 60, generation: diskGeneration)
        } else if force {
            await diskCache.removeEntry(key: key.diskKey, generation: diskGeneration)
        }
        return result
    }

    private func remoteContexts(repositoryURL: URL) async -> [RemoteContext] {
        if let contextTask { return await contextTask.value }
        let task = Task { await loadRemoteContexts(repositoryURL: repositoryURL) }
        contextTask = task
        let result = await task.value
        contextTask = nil
        return result
    }

    private func loadRemoteContexts(repositoryURL: URL) async -> [RemoteContext] {
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
        var result: [RemoteContext] = []
        for (remote, value) in remoteURLs.sorted(by: { $0.0 < $1.0 }) {
            guard !value.isEmpty, let identity = GitRemoteIdentityResolver.identity(
                from: value,
                knownGitLabHosts: knownGitLabHosts,
                knownHosts: knownHosts
            ) else { continue }
            let defaultRef = await GitStatusService.shared.defaultBranch(in: repositoryURL, remote: remote)
            let defaultTip: String?
            if let defaultRef { defaultTip = await GitStatusService.shared.tipHash(for: defaultRef, in: repositoryURL) } else { defaultTip = nil }
            result.append(RemoteContext(name: remote, identity: identity, defaultRef: defaultRef, defaultTip: defaultTip))
        }
        return result
    }

    private func detectResolved(branch: String, tip: String, key: CacheKey, remoteContexts: [RemoteContext], accounts: [GitProviderAccount], sourceRemoteName: String?, sourceBranch: String) async -> BranchMergeAssessment {
        let sourceContext = remoteContexts.first { $0.name == sourceRemoteName }
            ?? remoteContexts.first { $0.name == "origin" }
            ?? remoteContexts.first
        guard let sourceContext else {
            return publish(.init(branch: branch, tipSHA: tip, state: .unknown, evidence: [],
                                 detail: "No supported GitHub or GitLab remote could be resolved.", checkedAt: .now), key: key)
        }

        for context in remoteContexts {
            if let defaultRef = context.defaultRef, let defaultTip = context.defaultTip,
               await GitStatusService.shared.branchTipIsAncestor(tip, of: defaultTip, in: URL(fileURLWithPath: key.repository)) {
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
                    sourceBranch: sourceBranch,
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
        return assessment
    }

    private func updateAssessment(_ result: BranchMergeAssessment) {
        if let previous = assessments[result.branch],
           previous.branch == result.branch, previous.tipSHA == result.tipSHA,
           previous.state == result.state, previous.evidence == result.evidence,
           previous.detail == result.detail {
            return
        }
        assessments[result.branch] = result
    }

    private struct CacheKey: Hashable {
        let repository: String; let branch: String; let tip: String; let context: String
        var diskKey: String {
            "branch-merge-v1." + [repository, branch, tip, context].map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
        }
    }
    private struct RemoteContext: Sendable { let name: String; let identity: GitRemoteIdentity; let defaultRef: String?; let defaultTip: String? }
}

private extension GitRemoteIdentity {
    var repositoryIdentity: GitRepositoryIdentity {
        GitRepositoryIdentity(provider: provider, hostURL: hostURL, owner: ownerPath, name: repositoryName)
    }
}

