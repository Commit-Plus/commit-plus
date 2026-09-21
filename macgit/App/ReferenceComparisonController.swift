// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

@MainActor @Observable
final class ReferenceComparisonController {
    let repositoryURL: URL
    let isBranchComparison: Bool
    let title: String
    private(set) var baseRef: String
    private(set) var targetRef: String
    private(set) var mode: ReferenceComparisonMode
    private(set) var branches: [ComparisonBranch] = []
    private(set) var snapshot: ReferenceComparisonSnapshot?
    private(set) var files: [CommitFileChange] = []
    private(set) var baseCommits: [Commit] = []
    private(set) var targetCommits: [Commit] = []
    private(set) var selectedFile: CommitFileChange?
    private(set) var patch: ReferenceComparisonPatch?
    private(set) var error: String?
    private(set) var fileError: String?
    private(set) var baseCommitsError: String?
    private(set) var targetCommitsError: String?
    private(set) var isLoading = false
    private(set) var isLoadingPatch = false
    private(set) var isLoadingBaseCommits = false
    private(set) var isLoadingTargetCommits = false
    private(set) var isCancelled = false
    @ObservationIgnored private let service: any ReferenceComparisonServing
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var patchID = UUID()
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?
    @ObservationIgnored private(set) var patchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var baseCommitsTask: Task<Void, Never>?
    @ObservationIgnored private(set) var targetCommitsTask: Task<Void, Never>?

    init(repositoryURL: URL, baseRef: String, targetRef: String, isBranchComparison: Bool = true,
         title: String = "Compare Branches", service: any ReferenceComparisonServing = GitStatusService.shared) {
        self.repositoryURL = repositoryURL
        self.baseRef = baseRef
        self.targetRef = targetRef
        self.isBranchComparison = isBranchComparison
        self.title = title
        self.service = service
        self.mode = isBranchComparison ? .mergeBase : .tips
    }

    func setBase(_ ref: String) {
        guard baseRef != ref else { return }
        baseRef = ref
        reload()
    }

    func setTarget(_ ref: String) {
        guard targetRef != ref else { return }
        targetRef = ref
        reload()
    }

    func swap() {
        (baseRef, targetRef) = (targetRef, baseRef)
        reload()
    }

    func setMode(_ mode: ReferenceComparisonMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        reload(reuseSnapshot: true)
    }

    func cancel() {
        requestID = UUID()
        patchID = UUID()
        loadTask?.cancel()
        patchTask?.cancel()
        baseCommitsTask?.cancel()
        targetCommitsTask?.cancel()
        isLoading = false
        isLoadingPatch = false
        isLoadingBaseCommits = false
        isLoadingTargetCommits = false
        isCancelled = true
    }

    func reload(reuseSnapshot: Bool = false) {
        let previousSnapshot = reuseSnapshot ? snapshot : nil
        cancel()
        let id = requestID
        let base = baseRef
        let target = targetRef
        let requestedMode = mode
        isCancelled = false
        isLoading = true
        error = nil
        fileError = nil
        files = []
        selectedFile = nil
        patch = nil
        snapshot = previousSnapshot
        if previousSnapshot == nil {
            baseCommits = []
            targetCommits = []
        }
        baseCommitsError = nil
        targetCommitsError = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                if isBranchComparison && (branches.isEmpty || !reuseSnapshot) {
                    let available = try await service.comparisonBranches(in: repositoryURL)
                    guard isCurrent(id) else { return }
                    branches = available
                }
                guard !base.isEmpty, !target.isEmpty else {
                    isLoading = false
                    return
                }
                let resolved: ReferenceComparisonSnapshot
                if let previousSnapshot {
                    resolved = previousSnapshot
                } else {
                    resolved = try await service.comparisonSnapshot(base: base, target: target,
                        branchesOnly: isBranchComparison, in: repositoryURL)
                }
                guard isCurrent(id) else { return }
                snapshot = resolved
                if isBranchComparison {
                    if baseCommits.isEmpty { loadMoreCommits(targetSide: false) }
                    if targetCommits.isEmpty { loadMoreCommits(targetSide: true) }
                }
                let changes = try await service.comparisonFiles(snapshot: resolved, mode: requestedMode, in: repositoryURL)
                guard isCurrent(id) else { return }
                files = changes
                isLoading = false
            } catch {
                guard isCurrent(id) else { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func selectFile(_ file: CommitFileChange?) {
        patchTask?.cancel()
        patchID = UUID()
        selectedFile = file
        patch = nil
        fileError = nil
        isLoadingPatch = false
        guard let file, let snapshot, files.contains(file), !isCancelled else { return }
        let id = requestID
        let fileID = patchID
        let requestedMode = mode
        isLoadingPatch = true
        patchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.comparisonPatch(file: file, snapshot: snapshot, mode: requestedMode, in: repositoryURL)
                guard isCurrent(id), patchID == fileID else { return }
                patch = result
                isLoadingPatch = false
            } catch {
                guard isCurrent(id), patchID == fileID else { return }
                fileError = error.localizedDescription
                isLoadingPatch = false
            }
        }
    }

    func loadMoreCommits(targetSide: Bool) {
        guard let snapshot, !isCancelled else { return }
        let count = targetSide ? targetCommits.count : baseCommits.count
        let total = targetSide ? snapshot.targetOnlyCount : snapshot.baseOnlyCount
        guard count < total, !(targetSide ? isLoadingTargetCommits : isLoadingBaseCommits) else { return }
        let id = requestID
        if targetSide {
            isLoadingTargetCommits = true
            targetCommitsError = nil
        } else {
            isLoadingBaseCommits = true
            baseCommitsError = nil
        }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let commits = try await service.comparisonCommits(snapshot: snapshot, targetSide: targetSide,
                    skip: count, limit: 100, in: repositoryURL)
                guard isCurrent(id) else { return }
                if targetSide {
                    targetCommits += commits
                    isLoadingTargetCommits = false
                } else {
                    baseCommits += commits
                    isLoadingBaseCommits = false
                }
            } catch {
                guard isCurrent(id) else { return }
                if targetSide {
                    targetCommitsError = error.localizedDescription
                    isLoadingTargetCommits = false
                } else {
                    baseCommitsError = error.localizedDescription
                    isLoadingBaseCommits = false
                }
            }
        }
        if targetSide { targetCommitsTask = task } else { baseCommitsTask = task }
    }

    private func isCurrent(_ id: UUID) -> Bool {
        !Task.isCancelled && requestID == id
    }
}
