//
//  SyncState.swift
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
import SwiftUI
import Combine
import Network

extension Notification.Name {
    static let repositoryDidChange = Notification.Name("macgit.repositoryDidChange")
    static let repositoryLocalStateDidRefresh = Notification.Name("macgit.repositoryLocalStateDidRefresh")
    static let repositoryRemoteRefsDidRefresh = Notification.Name("macgit.repositoryRemoteRefsDidRefresh")
    static let repositoryCurrentBranchDidChange = Notification.Name("macgit.repositoryCurrentBranchDidChange")
    static let repositoryBranchDidCreate = Notification.Name("macgit.repositoryBranchDidCreate")
}

private actor SyncRefreshCoordinator {
    private var localRefreshInFlight = false
    private var lastLocalRefreshDate: Date?
    private var automaticFetchInFlight = false
    private var lastAutomaticFetchDate = Date.distantPast

    func beginLocalRefresh(
        force: Bool,
        minimumInterval: TimeInterval,
        now: Date
    ) -> Bool {
        guard !localRefreshInFlight else { return false }
        if !force,
           let lastLocalRefreshDate,
           now.timeIntervalSince(lastLocalRefreshDate) < minimumInterval {
            return false
        }

        localRefreshInFlight = true
        return true
    }

    func finishLocalRefresh(at date: Date) {
        localRefreshInFlight = false
        lastLocalRefreshDate = date
    }

    func beginAutomaticFetch(
        force: Bool,
        minimumInterval: TimeInterval,
        now: Date
    ) -> Bool {
        guard !automaticFetchInFlight else { return false }
        if !force,
           now.timeIntervalSince(lastAutomaticFetchDate) < minimumInterval {
            return false
        }

        automaticFetchInFlight = true
        return true
    }

    func finishAutomaticFetch(succeeded: Bool, at date: Date) {
        automaticFetchInFlight = false
        if succeeded {
            lastAutomaticFetchDate = date
        }
    }
}

class SyncState: ObservableObject {
    @Published var commitBadgeCount: Int = 0
    @Published var stagedBadgeCount: Int = 0
    @Published var stashableCount: Int = 0
    @Published var pushBadgeCount: Int = 0
    @Published var pullBadgeCount: Int = 0
    @Published var errorMessage: String? = nil
    @Published var showingError: Bool = false
    @Published var conflictMessage: String? = nil
    @Published var showingConflict: Bool = false
    @Published var infoMessage: String? = nil
    @Published var showingInfo: Bool = false
    @Published var isCommitting: Bool = false
    @Published var isPushing: Bool = false
    @Published var isPulling: Bool = false
    @Published var isFetching: Bool = false
    @Published var isMerging: Bool = false
    @Published var isStashing: Bool = false
    @Published var isUpdatingCurrentBranch: Bool = false
    @Published var activeSyncBranch: String? = nil
    @Published var inProgressOperation: GitInProgressOperation? = nil

    var isAnySyncing: Bool {
        isCommitting || isPushing || isPulling || isFetching || isMerging || isStashing || isUpdatingCurrentBranch
    }

    private var backgroundTask: Task<Void, Never>? = nil
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "dev.thanhtran.macgit.sync-state.network")
    private let refreshCoordinator = SyncRefreshCoordinator()
    private var refreshGeneration = 0
    private var refreshedCurrentBranches: [URL: String] = [:]
    private static let backgroundRefreshInterval: Duration = .seconds(10)
    private static let localRefreshCoalescingInterval: TimeInterval = 2
    private static let autoFetchInterval: TimeInterval = 60

    init() {
        networkMonitor.start(queue: networkMonitorQueue)
    }

    deinit {
        networkMonitor.cancel()
    }

    func refresh(repositoryURL: URL, force: Bool = true) async {
        guard await refreshCoordinator.beginLocalRefresh(
            force: force,
            minimumInterval: Self.localRefreshCoalescingInterval,
            now: .now
        ) else {
            return
        }

        let generation = await MainActor.run { () -> Int in
            refreshGeneration += 1
            return refreshGeneration
        }
        async let loadedCurrentBranch = GitStatusService.shared.currentBranch(in: repositoryURL)

        let uncommittedCount = await GitStatusService.shared.uncommittedChangeCount(in: repositoryURL)
        let trackedCounts = await GitStatusService.shared.trackedStatusCounts(in: repositoryURL)
        await MainActor.run {
            guard generation == refreshGeneration else { return }
            self.commitBadgeCount = uncommittedCount
            self.stagedBadgeCount = trackedCounts.staged
            self.stashableCount = trackedCounts.staged + trackedCounts.unstaged
        }

        let counts = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
        let operation = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
        let currentBranch = await loadedCurrentBranch ?? ""
        let currentBranchDidChange = await MainActor.run { () -> Bool in
            // A checkout or another repository change can start a newer
            // refresh while this one is still reading Git state. Never let
            // the older snapshot overwrite the newer one.
            guard generation == refreshGeneration else { return false }
            self.pushBadgeCount = counts.ahead
            self.pullBadgeCount = counts.behind
            self.inProgressOperation = operation
            let previousBranch = refreshedCurrentBranches.updateValue(currentBranch, forKey: repositoryURL)
            return previousBranch != nil && previousBranch != currentBranch
        }

        if currentBranchDidChange {
            NotificationCenter.default.post(
                name: .repositoryCurrentBranchDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        }

        await refreshCoordinator.finishLocalRefresh(at: .now)
    }

    func startBackgroundSync(
        repositoryURL: URL,
        settings: RepoSettings,
        globalAutoFetchEnabled: Bool
    ) {
        stopBackgroundSync()
        let autoFetchEnabled = settings.resolvedAutoFetchEnabled(globalValue: globalAutoFetchEnabled)
        backgroundTask = Task {
            while !Task.isCancelled {
                if autoFetchEnabled,
                   networkMonitor.currentPath.status == .satisfied,
                   await performAutomaticFetch(
                       options: GitStatusService.FetchOptions(),
                       repositoryURL: repositoryURL,
                       force: false
                   ) {
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .repositoryRemoteRefsDidRefresh,
                                object: nil,
                                userInfo: ["repositoryURL": repositoryURL]
                            )
                        }
                }
                await refresh(repositoryURL: repositoryURL, force: false)
                try? await Task.sleep(for: Self.backgroundRefreshInterval)
            }
        }
    }

    @discardableResult
    func performAutomaticFetch(
        options: GitStatusService.FetchOptions,
        repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil,
        force: Bool
    ) async -> Bool {
        guard await refreshCoordinator.beginAutomaticFetch(
            force: force,
            minimumInterval: Self.autoFetchInterval,
            now: .now
        ) else {
            return false
        }

        do {
            try await GitStatusService.shared.fetch(
                options: options,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refreshCoordinator.finishAutomaticFetch(succeeded: true, at: .now)
            return true
        } catch {
            // Automatic fetch remains best effort. Manual actions surface errors.
            await refreshCoordinator.finishAutomaticFetch(succeeded: false, at: .now)
            return false
        }
    }

    func stopBackgroundSync() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    private func notifyRepositoryChanged(_ repositoryURL: URL) {
        NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
    }

    func showConflict(_ message: String) {
        conflictMessage = message
        showingConflict = true
    }

    func showInfo(_ message: String) {
        infoMessage = message
        showingInfo = true
    }

    func checkConflicts(repositoryURL: URL) async -> Bool {
        let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
        if hasConflicts {
            showConflict("There are unresolved merge conflicts. Please resolve them before proceeding.")
        }
        return hasConflicts
    }

    func performPush(
        options: GitStatusService.PushOptions,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPushing = true }
        defer {
            Task { @MainActor in
                isPushing = false
                activeSyncBranch = nil
            }
        }

        let remoteSupport = GitRemoteUndoSupport()
        var unpublishedBranches: [(local: String, remote: String)] = []
        for local in options.branches {
            let remoteBranch = options.branchMappings[local] ?? local
            guard !local.isEmpty, !remoteBranch.isEmpty else { continue }
            do {
                let existingHash = try await remoteSupport.remoteHash(remote: options.remote, branch: remoteBranch, in: repositoryURL)
                if existingHash == nil {
                    unpublishedBranches.append((local, remoteBranch))
                }
            } catch {
                // Pre-flight check failed; skip undo registration for this branch to avoid misclassifying it as new.
                continue
            }
        }

        do {
            await MainActor.run {
                activeSyncBranch = options.branches.count == 1 ? options.branches.first : nil
            }
            _ = try await GitStatusService.shared.push(
                options: options,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            for mapping in unpublishedBranches {
                if let remoteHash = try await remoteSupport.remoteHash(remote: options.remote, branch: mapping.remote, in: repositoryURL) {
                    await MainActor.run {
                        undoManager?.register(
                            GitUndoEntry(
                                repositoryURL: repositoryURL,
                                label: "Publish \(options.remote)/\(mapping.remote)",
                                undoOperation: .deleteRemoteBranch(remote: options.remote, branch: mapping.remote, expectedHash: remoteHash),
                                redoOperation: .pushBranch(remote: options.remote, localBranch: mapping.local, remoteBranch: mapping.remote),
                                confirmationMessage: "Undoing publish will delete '\(options.remote)/\(mapping.remote)' from the remote. Continue?"
                            )
                        )
                    }
                }
            }
        } catch {
            showError(Self.pushErrorMessage(error, options: options))
        }
    }

    nonisolated static func pushErrorMessage(
        _ error: Error,
        options: GitStatusService.PushOptions
    ) -> String {
        let message = error.localizedDescription
        let normalizedMessage = message.lowercased()
        if !options.branches.isEmpty,
           normalizedMessage.contains("non-fast-forward") || normalizedMessage.contains("fetch first") {
            return "\(message)\n\nIf you intentionally reset or rewrote published commits, right-click the local branch, open Push to, and choose a Force Push action. Review the remote commits before confirming."
        }
        let isTagRejection = normalizedMessage.contains("already exists")
            || normalizedMessage.contains("would clobber existing tag")
        let includesTags = !options.tags.isEmpty || options.pushTags

        guard includesTags, !options.forceTags, isTagRejection else {
            return message
        }

        return "\(message)\n\nHint: Right-click the updated tag and choose Force Push to → \(options.remote) to replace the remote tag."
    }

    func performTrackRemoteBranch(branch: String, upstream: String?, repositoryURL: URL) async {
        do {
            if let upstream {
                try await GitStatusService.shared.setUpstream(upstream: upstream, branch: branch, in: repositoryURL)
                await refresh(repositoryURL: repositoryURL)
                notifyRepositoryChanged(repositoryURL)
            } else {
                try await GitStatusService.shared.unsetUpstream(branch: branch, in: repositoryURL)
                await refresh(repositoryURL: repositoryURL)
                notifyRepositoryChanged(repositoryURL)
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performPull(
        remote: String,
        branch: String,
        options: GitStatusService.PullOptions,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPulling = true }
        defer {
            Task { @MainActor in
                isPulling = false
                activeSyncBranch = nil
            }
        }
        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        do {
            await MainActor.run { activeSyncBranch = branch }
            _ = try await GitStatusService.shared.pull(
                remote: remote,
                branch: branch,
                options: options,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Pull",
                            undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                            redoOperation: .resetHead(target: newHead, mode: .hard, expectedHead: oldHead),
                            confirmationMessage: "Undoing a pull will reset the current branch back to its previous commit. Continue?"
                        )
                    )
                }
            }
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred during Pull. Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performPullBranch(
        branch: String,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPulling = true }
        defer {
            Task { @MainActor in
                isPulling = false
                activeSyncBranch = nil
            }
        }
        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        do {
            await MainActor.run { activeSyncBranch = branch }
            _ = try await GitStatusService.shared.pullBranchFromUpstream(
                branch: branch,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Pull",
                            undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                            redoOperation: .resetHead(target: newHead, mode: .hard, expectedHead: oldHead),
                            confirmationMessage: "Undoing a pull will reset the current branch back to its previous commit. Continue?"
                        )
                    )
                }
            }
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred during Pull. Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performPushToTracked(
        branch: String,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
            showError("Branch '\(branch)' has no upstream to push to.")
            return
        }
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            showError("Could not parse upstream '\(upstream)'.")
            return
        }
        let options = GitStatusService.PushOptions(
            remote: parts[0],
            branches: [branch],
            branchMappings: [branch: parts[1]]
        )
        await performPush(
            options: options,
            repositoryURL: repositoryURL,
            undoManager: undoManager,
            credentialResolver: credentialResolver
        )
    }

    func performRebaseOnto(branch: String, repositoryURL: URL, undoManager: GitUndoManager? = nil) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        do {
            try await GitStatusService.shared.rebaseCommit(branch, in: repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Rebase onto \(branch)",
                            undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                            redoOperation: .rebaseOnto(commit: branch)
                        )
                    )
                }
            }
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred during Rebase. Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performFetch(
        options: GitStatusService.FetchOptions,
        repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        await MainActor.run { isFetching = true }
        defer { Task { @MainActor in isFetching = false } }
        do {
            try await GitStatusService.shared.fetch(
                options: options,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performFetchBranch(
        branch: String,
        repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        await MainActor.run { isFetching = true }
        defer { Task { @MainActor in isFetching = false } }
        guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
            showError("Branch '\(branch)' has no upstream to fetch from.")
            return
        }
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else {
            showError("Could not parse upstream '\(upstream)'.")
            return
        }
        do {
            try await GitStatusService.shared.fetchBranch(
                remote: parts[0],
                branch: parts[1],
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performFetchAndFastForwardBranch(
        branch: String,
        repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        await MainActor.run {
            isFetching = true
            activeSyncBranch = branch
        }
        defer {
            Task { @MainActor in
                isFetching = false
                activeSyncBranch = nil
            }
        }
        do {
            _ = try await GitStatusService.shared.fetchAndFastForwardBranchFromUpstream(
                branch: branch,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred while updating \(branch). Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performCurrentBranchIntegrationUpdate(
        status: CurrentBranchIntegrationStatus,
        preferredRemote: String?,
        gitFlowConfiguration: GitFlowConfiguration,
        pullStrategy: PullStrategy,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        let operationAlreadyRunning = await MainActor.run { isAnySyncing }
        guard !operationAlreadyRunning else {
            showInfo("Wait for the current repository operation to finish.")
            return
        }
        guard !(await checkConflicts(repositoryURL: repositoryURL)) else { return }
        guard await GitStatusService.shared.inProgressOperation(in: repositoryURL) == nil else {
            showInfo("Finish the current Git operation before updating this branch.")
            return
        }
        guard (try? await GitStashUndoSupport().isWorkingTreeClean(in: repositoryURL)) == true else {
            showInfo("Commit or stash your working copy changes before updating this branch.")
            return
        }
        guard await GitStatusService.shared.currentBranch(in: repositoryURL) == status.branch else {
            showInfo("The current branch changed. Review the warning again before updating.")
            return
        }

        await MainActor.run {
            isUpdatingCurrentBranch = true
            activeSyncBranch = status.branch
        }
        defer {
            Task { @MainActor in
                isUpdatingCurrentBranch = false
                activeSyncBranch = nil
            }
        }

        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        do {
            try await GitStatusService.shared.fetchCurrentBranchIntegrationRefs(
                status,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )

            var refreshedStatus = await GitStatusService.shared.currentBranchIntegrationStatus(
                branch: status.branch,
                preferredRemote: preferredRemote,
                gitFlowConfiguration: gitFlowConfiguration,
                in: repositoryURL
            )
            if let upstreamStatus = refreshedStatus,
               upstreamStatus.upstreamBehindCount > 0 {
                _ = try await GitStatusService.shared.pullBranchFromUpstream(
                    branch: status.branch,
                    in: repositoryURL,
                    options: GitStatusService.PullOptions(
                        rebaseInstead: pullStrategy == .rebase
                    ),
                    credentialResolver: credentialResolver
                )
                refreshedStatus = await GitStatusService.shared.currentBranchIntegrationStatus(
                    branch: status.branch,
                    preferredRemote: preferredRemote,
                    gitFlowConfiguration: gitFlowConfiguration,
                    in: repositoryURL
                )
            }

            if let baseStatus = refreshedStatus,
               baseStatus.baseBehindCount > 0,
               let baseRef = baseStatus.baseRef {
                _ = try await GitStatusService.shared.merge(
                    branch: baseRef,
                    options: GitStatusService.MergeOptions(
                        message: "Merge \(baseRef) into \(status.branch)"
                    ),
                    in: repositoryURL
                )
            }

            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Update \(status.branch)",
                            undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                            redoOperation: .resetHead(target: newHead, mode: .hard, expectedHead: oldHead),
                            confirmationMessage: "Undoing this update will reset \(status.branch) to its previous commit. Continue?"
                        )
                    )
                }
            }

            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            if await GitStatusService.shared.hasConflicts(in: repositoryURL) {
                showConflict("Updating \(status.branch) produced conflicts. Resolve them in the File status view.")
            } else {
                showError(error.localizedDescription)
            }
        }
    }

    func performCommit(
        message: String,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        noVerify: Bool = false,
        signOff: Bool = false,
        commitAllChanges: Bool = false
    ) async {
        await MainActor.run { isCommitting = true }
        defer { Task { @MainActor in isCommitting = false } }
        do {
            if commitAllChanges {
                try await GitStatusService.shared.stageAllChanges(in: repositoryURL)
            }
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.commit(
                message: message,
                in: repositoryURL,
                noVerify: noVerify,
                signOff: signOff
            )
            let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            if let oldHead, let newHead, oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntryFactory.commit(
                            repositoryURL: repositoryURL,
                            oldHead: oldHead,
                            newHead: newHead,
                            message: message,
                            noVerify: noVerify,
                            signOff: signOff
                        )
                    )
                }
            }
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performMerge(branch: String, options: GitStatusService.MergeOptions, repositoryURL: URL) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isMerging = true }
        defer { Task { @MainActor in isMerging = false } }
        do {
            _ = try await GitStatusService.shared.merge(branch: branch, options: options, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred during Merge. Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performStash(
        options: GitStatusService.StashOptions,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil
    ) async {
        await MainActor.run { isStashing = true }
        defer { Task { @MainActor in isStashing = false } }
        do {
            try await GitStatusService.shared.stash(options: options, in: repositoryURL)
            let support = GitStashUndoSupport()
            let hash = try await support.hash(for: "stash@{0}", in: repositoryURL)
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Stash changes",
                        undoOperation: .stashApplyAndDrop(hash: hash),
                        redoOperation: .stashPush(
                            message: options.message,
                            keepIndex: options.keepIndex,
                            paths: options.paths,
                            includeUntracked: options.includeUntracked
                        )
                    )
                )
            }
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            showError(error.localizedDescription)
        }
    }
}
