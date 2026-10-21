//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

extension MainWindowView {
    @MainActor
    func authorizePullRequestAccess(
        forceRefresh: Bool = false,
        presentNotice: Bool = true
    ) async -> Bool {
        let decision = await repositoryVisibilityController.accessDecision(
            for: .pullRequests,
            repositoryURL: repositoryURL,
            accounts: providerAccountController.accounts,
            entitlement: accountController.entitlement,
            policy: featureAccessController.policy,
            forceRefresh: forceRefresh
        )
        guard !Task.isCancelled else { return false }
        pullRequestAccessDecision = decision
        if case .denied(let denial) = decision, presentNotice {
            if denial == .requiresPro {
                proUpgradeErrorMessage = nil
                proUpgradePresentation = ProUpgradePresentation(feature: .pullRequests)
            } else {
                featureAccessNotice = FeatureAccessNotice(feature: .pullRequests, denial: denial)
            }
        }
        return decision.isAllowed
    }

    func openPullRequest(branch: String) async {
        guard await authorizePullRequestAccess() else { return }
        guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
            await MainActor.run {
                syncState.showError("Branch '\(branch)' has no upstream. Push it first to create a pull request.")
            }
            return
        }
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else {
            await MainActor.run {
                syncState.showError("Could not parse upstream '\(upstream)'.")
            }
            return
        }
        let remoteName = parts[0]
        let remoteBranch = parts[1]
        let remoteURL = await GitStatusService.shared.remoteURL(remote: remoteName, in: repositoryURL)
        guard let url = PullRequestURLBuilder.build(remoteURL: remoteURL, branch: remoteBranch) else {
            await MainActor.run {
                syncState.showError("Remote '\(remoteName)' is not a recognized pull request host (GitHub, GitLab, or Bitbucket).")
            }
            return
        }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    func prepareCreatePullRequest(branch: String) {
        presentCreatePullRequestWindow(sourceBranch: branch)
    }

    func prepareCreatePullRequest() {
        presentCreatePullRequestWindow(sourceBranch: nil)
    }

    func resolveOpenPullRequest(
        remote: String,
        sourceBranch: String
    ) async -> PullRequestSummary? {
        guard await authorizePullRequestAccess(presentNotice: false) else { return nil }
        return try? await pullRequestController.openPullRequest(
            sourceBranch: sourceBranch,
            repositoryURL: repositoryURL,
            remoteName: remote
        )
    }

    func showPullRequestDetail(
        _ pullRequest: PullRequestSummary,
        remoteName: String? = nil
    ) async {
        // Opening from the sidebar may need access checks and a list load for another remote
        // before the window appears, so show progress instead of a silent delay.
        let progressID = remoteName.map { _ in
            operationProgress.begin(message: "Opening Pull Request #\(pullRequest.number)...", canCancel: false)
        }
        let switchedRemote = await preparePullRequestDetail(remoteName: remoteName)
        if let progressID { operationProgress.end(progressID) }
        guard let switchedRemote else { return }
        if !switchedRemote,
           selectedPullRequestID == pullRequest.id,
           pullRequestDetailWindow.activateIfPresented() { return }

        pullRequestDetailWindow.close()
        pullRequestController.clearSelectedDetail()
        selectedPullRequestID = pullRequest.id
        pullRequestDetailWindow.show(
            title: "Pull Request #\(pullRequest.number) — \(repositoryURL.lastPathComponent)",
            content: PullRequestDetailWindowContent(
                controller: pullRequestController,
                selectedPullRequestID: pullRequest.id,
                authorizeAction: { await authorizePullRequestAccess() },
                onClose: closePullRequestDetail
            )
            .environmentObject(appState)
            .environment(\.appTextScale, appState.textSize.scale)
            .sheetPresentationScope(),
            onClose: closePullRequestDetail
        )
        await pullRequestController.loadPullRequestDetail(pullRequest)
    }

    /// Authorizes access and, when opened for a specific remote, switches the list to it so the list,
    /// the selection, and the detail window's actions all target the same repository.
    /// Returns whether the remote was switched, or nil when the detail should not open.
    private func preparePullRequestDetail(remoteName: String?) async -> Bool? {
        guard await authorizePullRequestAccess() else { return nil }
        guard let remoteName,
              remoteName != pullRequestController.listRemoteName || !pullRequestController.hasLoadedList else {
            return false
        }
        await pullRequestController.loadPullRequests(repositoryURL: repositoryURL, remoteName: remoteName)
        guard !Task.isCancelled else { return nil }
        // A newer request for another remote superseded this load; its list is not ours to open from.
        if let loadedRemoteName = pullRequestController.listRemoteName,
           loadedRemoteName != remoteName { return nil }
        guard pullRequestController.hasLoadedList else {
            syncState.showError(pullRequestController.errorMessage ?? "Pull request details are unavailable.")
            return nil
        }
        return true
    }

    func closePullRequestDetail() {
        pullRequestDetailWindow.close()
        selectedPullRequestID = nil
        pullRequestController.clearSelectedDetail()
    }

    /// The in-app "pull request created" notification the user activated for this repository.
    var pendingPullRequestNotification: AppNotification? {
        guard let notification = appNotificationController.pendingPullRequest,
              notification.repositoryURL.resolvingSymlinksInPath().standardizedFileURL
                == repositoryURL.resolvingSymlinksInPath().standardizedFileURL else { return nil }
        return notification
    }

    func submitCreatePullRequest(_ draft: PullRequestDraft) async {
        guard await authorizePullRequestAccess(presentNotice: false) else {
            let message = "Pull request access is unavailable for this repository."
            pullRequestController.detailErrorMessage = message
            PullRequestUserNotification.creationFailed(message: message, repositoryURL: repositoryURL)
            return
        }
        let remoteName = pullRequestController.createDraftSeed?.remoteName
        do {
            _ = try await prepareRemoteBranchForPullRequest(branch: draft.sourceBranch)
            if let result = await pullRequestController.createPullRequest(draft) {
                await MainActor.run {
                    createPullRequestWindow.close()
                    if let detailErrorMessage = pullRequestController.detailErrorMessage {
                        syncState.showError(detailErrorMessage)
                        pullRequestController.detailErrorMessage = nil
                    }
                    PullRequestUserNotification.created(
                        result.summary,
                        repositoryURL: repositoryURL,
                        warnings: result.warnings
                    )
                }
                await appNotificationController.recordPullRequestCreated(
                    result.summary,
                    repositoryURL: repositoryURL,
                    remoteName: remoteName
                )
            } else {
                let message = pullRequestController.detailErrorMessage ?? "Could not create pull request."
                PullRequestUserNotification.creationFailed(message: message, repositoryURL: repositoryURL)
            }
        } catch {
            await MainActor.run {
                let message = error.localizedDescription
                pullRequestController.detailErrorMessage = message
                PullRequestUserNotification.creationFailed(message: message, repositoryURL: repositoryURL)
            }
        }
    }

    @MainActor
    private func presentCreatePullRequestWindow(sourceBranch: String?) {
        guard !createPullRequestWindow.activateIfPresented() else { return }
        pullRequestController.dismissCreatePullRequest()
        createPullRequestWindow.show(
            repositoryName: repositoryURL.lastPathComponent,
            content: CreatePullRequestPreparationView(
                controller: pullRequestController,
                windowController: createPullRequestWindow,
                repositoryURL: repositoryURL,
                loadDraft: { try await loadPullRequestDraft(sourceBranch: sourceBranch) },
                authorizeAction: { await authorizePullRequestAccess(presentNotice: false) },
                onGenerateText: { sourceBranch, targetBranch in
                    try await generatePullRequestText(sourceBranch: sourceBranch, targetBranch: targetBranch)
                },
                onCancel: {
                    pullRequestController.dismissCreatePullRequest()
                    createPullRequestWindow.close()
                },
                onCreate: { await submitCreatePullRequest($0) }
            )
            .environmentObject(appState),
            onClose: { pullRequestController.dismissCreatePullRequest() }
        )
    }

    @MainActor
    private func loadPullRequestDraft(sourceBranch: String?) async throws -> PullRequestDraftSeed {
        let remote: String?
        if let sourceBranch {
            if let upstream = await GitStatusService.shared.upstreamBranch(for: sourceBranch, in: repositoryURL) {
                remote = try parseRemoteBranch(upstream).remote
            } else {
                remote = try await defaultPullRequestRemote()
            }
        } else {
            remote = nil
        }
        try Task.checkCancellation()
        await pullRequestController.prepareCreatePullRequest(
            repositoryURL: repositoryURL, remoteName: remote, sourceBranch: sourceBranch
        )
        try Task.checkCancellation()
        guard let seed = pullRequestController.createDraftSeed else {
            throw GitError.commandFailed(pullRequestController.detailErrorMessage ?? "Pull request creation is unavailable.")
        }
        return seed
    }

    @MainActor
    func generatePullRequestText(
        sourceBranch: String,
        targetBranch: String
    ) async throws -> PullRequestAIDraftContent {
        let remoteName = pullRequestController.createDraftSeed?.remoteName
        let draftRepositoryURL = repositoryURL
        let budget = aiProviderController.selectedDescriptor.inputCharacterBudget
        let comparison = try await GitStatusService.shared.pullRequestComparison(
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            remoteName: remoteName,
            in: draftRepositoryURL,
            characterBudget: budget
        )
        let question = """
            Write one concise, human-readable pull request title and a concise, reviewer-friendly description that accurately summarize these changes.

            Return exactly this format:
            <title on the first line, without Markdown, quotes, or a label>

            <description starting after the blank line; use Markdown headings and bullets when useful>

            Include only details supported by the supplied changes. Do not invent testing or behavior.
            """
        let answer = try await aiProviderController.answerRepositoryAnalysisQuestion(
            repositoryURL: draftRepositoryURL,
            branchName: sourceBranch,
            question: question,
            result: comparison.toolResult(characterBudget: budget),
            currentFingerprint: {
                try await GitStatusService.shared.pullRequestComparisonFingerprint(
                    sourceBranch: sourceBranch,
                    targetBranch: targetBranch,
                    remoteName: remoteName,
                    in: draftRepositoryURL
                )
            }
        )
        let draft = PullRequestAIDraftContent(generatedResponse: answer.text)
        guard !draft.title.isEmpty || !draft.description.isEmpty else { throw RepositoryAIError.emptyResponse }
        return draft
    }

    func prepareRemoteBranchForPullRequest(branch: String) async throws -> String {
        let localBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localBranch.isEmpty else {
            throw GitError.commandFailed("Branch name is required.")
        }

        if let upstream = await GitStatusService.shared.upstreamBranch(for: localBranch, in: repositoryURL) {
            let remoteBranch = try parseRemoteBranch(upstream)
            if let status = await GitStatusService.shared.branchSyncStatus(for: localBranch, in: repositoryURL) {
                if status.behind > 0 {
                    throw GitError.commandFailed("Branch '\(localBranch)' is behind '\(upstream)'. Pull or rebase it before creating a pull request.")
                }
                if status.ahead > 0 {
                    try await pushBranchForPullRequest(
                        localBranch: localBranch,
                        remote: remoteBranch.remote,
                        remoteBranch: remoteBranch.branch,
                        setUpstream: false
                    )
                }
            }
            return remoteBranch.remote
        }

        let remote = try await defaultPullRequestRemote()
        try await pushBranchForPullRequest(
            localBranch: localBranch,
            remote: remote,
            remoteBranch: localBranch,
            setUpstream: true
        )
        return remote
    }

    func defaultPullRequestRemote() async throws -> String {
        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        guard !remotes.isEmpty else {
            throw GitError.commandFailed("No remotes configured. Add a remote before creating a pull request.")
        }
        if let preferred = repoSettings.defaultRemoteName, remotes.contains(preferred) {
            return preferred
        }
        return remotes.first(where: { $0 == "origin" }) ?? remotes[0]
    }

    func parseRemoteBranch(_ upstream: String) throws -> (remote: String, branch: String) {
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw GitError.commandFailed("Could not parse upstream '\(upstream)'.")
        }
        return (parts[0], parts[1])
    }

    func pushBranchForPullRequest(
        localBranch: String,
        remote: String,
        remoteBranch: String,
        setUpstream: Bool
    ) async throws {
        await MainActor.run {
            syncState.isPushing = true
            syncState.activeSyncBranch = localBranch
        }
        defer {
            Task { @MainActor in
                syncState.isPushing = false
                syncState.activeSyncBranch = nil
            }
        }

        let options = GitStatusService.PushOptions(
            remote: remote,
            branches: [localBranch],
            branchMappings: [localBranch: remoteBranch]
        )
        _ = try await GitStatusService.shared.push(
            options: options,
            in: repositoryURL,
            credentialResolver: providerCredentialResolver
        )
        if setUpstream {
            try await GitStatusService.shared.setUpstream(
                upstream: "\(remote)/\(remoteBranch)",
                branch: localBranch,
                in: repositoryURL
            )
        }
        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }

    func openPullRequest(remote: String, branch: String) async {
        guard await authorizePullRequestAccess() else { return }
        let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        guard let url = PullRequestURLBuilder.build(remoteURL: remoteURL, branch: branch) else {
            await MainActor.run {
                syncState.showError("Remote '\(remote)' is not a recognized pull request host (GitHub, GitLab, or Bitbucket).")
            }
            return
        }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    func browserURL(from remoteURLString: String) -> URL? {
        var cleaned = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("git@") {
            let withoutPrefix = cleaned.dropFirst("git@".count)
            if let colonIndex = withoutPrefix.firstIndex(of: ":") {
                let host = withoutPrefix[..<colonIndex]
                let path = withoutPrefix[withoutPrefix.index(after: colonIndex)...]
                cleaned = "https://\(host)/\(path)"
            }
        }
        if cleaned.hasPrefix("ssh://") {
            cleaned = String(cleaned.dropFirst("ssh://".count))
            if cleaned.hasPrefix("git@") {
                cleaned = String(cleaned.dropFirst("git@".count))
            }
            cleaned = "https://\(cleaned)"
        }
        if cleaned.hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(".git".count))
        }
        return URL(string: cleaned)
    }
}
