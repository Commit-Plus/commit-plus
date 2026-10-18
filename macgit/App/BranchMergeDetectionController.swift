// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

@MainActor
final class BranchMergeDetectionController: ObservableObject {
    @Published private(set) var assessments: [String: BranchMergeAssessment] = [:]
    @Published private(set) var loadingBranches: Set<String> = []
    private var requestIDs: [String: UUID] = [:]
    private var contextTask: Task<[RemoteContext], Never>?
    private var jobs: [String: Task<Void, Never>] = [:]
    private var queue: [(String, UUID, @MainActor () async -> Void)] = []
    private var activeJobs = 0

    private weak var providerAccountController: GitProviderAccountController?
    private let tokenVault: GitProviderTokenVault
    private let services: [GitProviderKind: any BranchMergeEvidenceProviding]
    private var generation = UUID()
    private var openedRepositoryPath: String?
    private var excludedBranches: Set<String> = ["main", "master", "develop"]

    init(
        providerAccountController: GitProviderAccountController? = nil,
        tokenVault: GitProviderTokenVault? = nil,
        services: [GitProviderKind: any BranchMergeEvidenceProviding]? = nil
    ) {
        self.providerAccountController = providerAccountController
        self.tokenVault = tokenVault ?? KeychainGitProviderTokenVault()
        self.services = services ?? [
            .github: GitHubBranchMergeEvidenceService(),
            .gitlab: GitLabBranchMergeEvidenceService(),
        ]
    }

    func assessment(for branch: String, repositoryURL: URL, configuration: GitFlowConfiguration? = nil) -> BranchMergeAssessment? {
        guard isCleanupCandidate(branch, configuration: configuration) else { return nil }
        return assessments[branch]
    }

    func isCleanupCandidate(_ branch: String, configuration: GitFlowConfiguration? = nil) -> Bool {
        guard !excludedBranches.contains(branch) else { return false }
        if let configuration {
            let configuration = configuration.normalized()
            guard branch != configuration.mainBranch, branch != configuration.developBranch else { return false }
        }
        return true
    }

    func invalidate() {
        generation = UUID()
        requestIDs.removeAll()
        for job in jobs.values { job.cancel() }
        jobs.removeAll()
        queue.removeAll()
        contextTask?.cancel()
        contextTask = nil
        assessments.removeAll()
        loadingBranches.removeAll()
    }

    func refresh(
        branches: [String],
        repositoryURL: URL,
        entitlement: AccountEntitlement,
        policy: FeatureAccessPolicy,
        configuration: GitFlowConfiguration = GitFlowConfiguration(),
        force: Bool = false
    ) async {
        let repositoryPath = repositoryURL.standardizedFileURL.path
        // Merge status belongs to an open-repository session, not the sidebar's
        // local-status/fetch polling lifecycle. Only explicit refresh bypasses this.
        guard force || openedRepositoryPath != repositoryPath else { return }
        guard FeatureAccessResolver(policy: policy).decision(
            for: .branchMergeDetection,
            entitlement: entitlement
        ).isAllowed else {
            invalidate()
            return
        }
        let isOpening = openedRepositoryPath != repositoryPath
        openedRepositoryPath = repositoryPath
        let currentGeneration = generation
        let configuration = configuration.normalized()
        excludedBranches = ["main", "master", "develop", configuration.mainBranch, configuration.developBranch]
        if isOpening,
           let saved = try? await LocalDataStore.shared.readValue(
               [String: BranchMergeAssessment].self, in: "branchMergeAssessments", id: repositoryPath
           ), generation == currentGeneration {
            assessments = saved.filter { isCleanupCandidate($0.key, configuration: configuration) }
        }
        // Read full ref names: short names can acquire a heads/ prefix when a
        // tag has the same name, which would incorrectly remove a cached hint.
        // Include remote tips so a fetch can reveal newly merged branches.
        let output = try? await GitStatusService.shared.runGit(
            arguments: ["for-each-ref", "--format=%(refname)%09%(objectname)%09%(upstream)", "refs/heads/", "refs/remotes/"],
            in: repositoryURL
        )
        guard generation == currentGeneration, !Task.isCancelled, let output else { return }
        let contexts = await remoteContexts(repositoryURL: repositoryURL)
        guard generation == currentGeneration, !Task.isCancelled else { return }
        excludedBranches.formUnion(contexts.compactMap { context in
            context.defaultRef.map { String($0.split(separator: "/", maxSplits: 1).last ?? "") }
        })
        var refs: [String: (String, String)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.count == 3, fields[0].hasPrefix("refs/heads/") {
                refs[String(fields[0].dropFirst("refs/heads/".count))] = (fields[1], fields[2])
            }
        }
        for removed in Set(assessments.keys).subtracting(refs.keys).union(excludedBranches) {
            if assessments[removed] != nil { assessments.removeValue(forKey: removed) }
        }
        for branch in Set(branches).sorted() {
            guard isCleanupCandidate(branch, configuration: configuration) else { continue }
            guard let (tip, _) = refs[branch] else { continue }
            jobs[branch]?.cancel()
            queue.removeAll { $0.0 == branch }
            let id = UUID()
            requestIDs[branch] = id
            loadingBranches.insert(branch)
            if assessments[branch]?.tipSHA != tip { assessments.removeValue(forKey: branch) }
            queue.append((branch, id, { [weak self] in
                guard let self else { return }
                let result = await detect(branch: branch, repositoryURL: repositoryURL,
                                          contexts: contexts, requestID: id)
                guard generation == currentGeneration, requestIDs[branch] == id else { return }
                if let result { updateAssessment(result) }
                loadingBranches.remove(branch)
                let snapshot = assessments
                try? await LocalDataStore.shared.transaction { transaction in
                    try transaction.set(snapshot, in: "branchMergeAssessments", id: repositoryPath)
                }
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
        let result = await detect(branch: branch, repositoryURL: repositoryURL)
        if let result { updateAssessment(result) }
        return result?.isFullyMerged == true ? result : nil
    }

    private func detect(branch: String, repositoryURL: URL, contexts: [RemoteContext]? = nil, requestID: UUID? = nil) async -> BranchMergeAssessment? {
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
        guard isCleanupCandidate(branch) else { return false }
        switch await GitFlowConfigurationStore().loadResult(in: repositoryURL) {
        case .value(let configuration):
            guard isCleanupCandidate(branch, configuration: configuration) else { return false }
        case .invalid:
            return false
        case .none:
            break
        }
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

