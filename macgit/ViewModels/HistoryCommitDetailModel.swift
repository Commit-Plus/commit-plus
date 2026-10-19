// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

@Observable @MainActor
final class HistoryCommitDetailModel {
    private struct Snapshot {
        let fileChanges: [CommitFileChange]
        let lineCounts: [String: FileLineChangeCount]
        let patchUnavailableReasons: [String: String]
        let selectedPath: String?
    }

    private struct DiffKey: Hashable {
        let commit: String
        let path: String
    }

    /// Diffs larger than this are not kept in `diffCache`, so a few huge files cannot pin a lot of memory.
    private static let maxCachedDiffLines = 20_000

    private(set) var commit: Commit?
    private(set) var fileChanges: [CommitFileChange] = []
    private(set) var lineCounts: [String: FileLineChangeCount] = [:]
    private(set) var patchUnavailableReasons: [String: String]?

    func patchDisabledReason(for files: [CommitFileChange]) -> String? {
        if patchController.isBusy { return "Another selected-patch operation is running." }
        if commit?.isMerge == true { return "Selected changes from merge commits are not supported." }
        guard let patchUnavailableReasons else { return "Checking patch availability…" }
        for file in files {
            if let reason = patchUnavailableReasons[file.path]
                ?? file.oldPath.flatMap({ patchUnavailableReasons[$0] }) { return reason }
        }
        return nil
    }

    var selectedFile: CommitFileChange? {
        didSet {
            guard oldValue != selectedFile else { return }
            diff = nil
            loadDiff()
        }
    }
    private(set) var diff: (commit: String, path: String, hunks: [DiffHunk])?
    private(set) var fullMessage: String?
    private(set) var isLoadingFullMessage = false
    var showingCommitInfo = false
    let patchController = CommitPatchController()

    @ObservationIgnored private let repositoryURL: URL
    @ObservationIgnored private var filesHash: String?
    @ObservationIgnored private var countsHash: String?
    @ObservationIgnored private var patchReasonsHash: String?
    @ObservationIgnored private var previousFile: CommitFileChange?
    @ObservationIgnored private var snapshotCache = BoundedMemoryCache<String, Snapshot>(capacity: 30)
    @ObservationIgnored private var diffCache = BoundedMemoryCache<DiffKey, [DiffHunk]>(capacity: 12)
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var diffGeneration = UUID()
    @ObservationIgnored private var messageGeneration = UUID()

    init(repositoryURL: URL) { self.repositoryURL = repositoryURL }

    func show(_ commit: Commit?, debounce: Bool) {
        guard self.commit?.hash != commit?.hash else { return }
        cacheCurrentSnapshot()
        cancelTasks()
        previousFile = selectedFile ?? previousFile
        self.commit = commit
        showingCommitInfo = false
        fullMessage = nil
        diff = nil
        if let commit, let snapshot = snapshotCache.value(for: commit.hash) {
            fileChanges = snapshot.fileChanges
            lineCounts = snapshot.lineCounts
            patchUnavailableReasons = snapshot.patchUnavailableReasons
            filesHash = commit.hash
            countsHash = commit.hash
            patchReasonsHash = commit.hash
            // Keep the user's current file selected when this commit has it, as the uncached path does.
            selectedFile = snapshot.fileChanges.first(where: { $0.path == previousFile?.path })
                ?? snapshot.fileChanges.first(where: { $0.path == snapshot.selectedPath })
                ?? snapshot.fileChanges.first
            previousFile = selectedFile
            // Assigning selectedFile normally starts the diff load; only load here if it did not.
            if diff == nil, diffTask == nil { loadDiff() }
            return
        }
        patchUnavailableReasons = nil
        fileChanges = []
        lineCounts = [:]
        filesHash = nil
        countsHash = nil
        patchReasonsHash = nil
        selectedFile = nil
        startLoading(debounce: debounce)
    }

    func suspend() {
        suspended = true
        cancelTasks()
    }

    func resume() {
        suspended = false
        startLoading(debounce: false)
        loadDiff()
        if showingCommitInfo, fullMessage == nil { loadFullMessage() }
    }

    func clearCache() {
        snapshotCache.removeAll()
        diffCache.removeAll()
    }

    private func cancelTasks() {
        generation = UUID()
        diffGeneration = UUID()
        messageGeneration = UUID()
        loadTask?.cancel()
        diffTask?.cancel()
        messageTask?.cancel()
        loadTask = nil
        diffTask = nil
        messageTask = nil
        isLoadingFullMessage = false
    }

    private func startLoading(debounce: Bool) {
        guard !suspended, loadTask == nil, let commit else { return }
        let token = generation
        let hash = commit.hash
        guard filesHash != hash || countsHash != hash || patchReasonsHash != hash else { return }
        loadTask = Task { [self] in
            defer { if generation == token { loadTask = nil } }
            if debounce {
                do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            }
            guard isCurrent(hash, token: token) else { return }
            async let reasons: [String: String]? = patchReasonsHash == hash
                ? nil : try? GitStatusService.shared.commitPatchUnavailableReasons(commit: hash, in: repositoryURL)
            async let counts: [String: FileLineChangeCount]? = countsHash == hash
                ? nil : try? GitStatusService.shared.commitLineChangeCounts(in: hash, in: repositoryURL)
            // A failed load leaves its hash unset, so the next load retries it and the
            // snapshot (which requires all three hashes) never caches a failure.
            if filesHash != hash {
                let files = try? await GitStatusService.shared.commitChangedFiles(in: hash, in: repositoryURL)
                guard isCurrent(hash, token: token) else { return }
                fileChanges = files ?? []
                if files != nil { filesHash = hash }
                let previousPath = (selectedFile ?? previousFile)?.path
                selectedFile = fileChanges.first(where: { $0.path == previousPath }) ?? fileChanges.first
                previousFile = selectedFile
            }
            let loadedReasons = await reasons
            let loadedCounts = await counts
            guard isCurrent(hash, token: token) else { return }
            if patchReasonsHash != hash {
                patchUnavailableReasons = loadedReasons ?? Dictionary(
                    uniqueKeysWithValues: fileChanges.map { ($0.path, "Unable to check patch availability. Select the commit again to retry.") })
                if loadedReasons != nil { patchReasonsHash = hash }
            }
            if countsHash != hash {
                lineCounts = loadedCounts ?? [:]
                if loadedCounts != nil { countsHash = hash }
            }
            cacheCurrentSnapshot()
        }
    }

    private func cacheCurrentSnapshot() {
        guard let hash = commit?.hash, filesHash == hash, countsHash == hash,
              patchReasonsHash == hash, let patchUnavailableReasons else { return }
        snapshotCache.insert(Snapshot(fileChanges: fileChanges, lineCounts: lineCounts,
            patchUnavailableReasons: patchUnavailableReasons, selectedPath: selectedFile?.path), for: hash)
    }

    private func isCurrent(_ hash: String, token: UUID) -> Bool {
        !Task.isCancelled && !suspended && generation == token && commit?.hash == hash
    }

    private func loadDiff() {
        diffTask?.cancel()
        diffTask = nil
        diffGeneration = UUID()
        guard !suspended, let commit, let file = selectedFile else { return }
        guard diff?.commit != commit.hash || diff?.path != file.path else { return }
        let key = DiffKey(commit: commit.hash, path: file.path)
        if let hunks = diffCache.value(for: key) {
            diff = (commit.hash, file.path, hunks)
            return
        }
        let token = diffGeneration
        diffTask = Task { [self] in
            defer { if diffGeneration == token { diffTask = nil } }
            let hunks = try? await GitStatusService.shared.commitDiff(for: file.path, in: commit.hash, in: repositoryURL)
            guard !Task.isCancelled, !suspended, diffGeneration == token,
                  self.commit?.hash == commit.hash, selectedFile == file else { return }
            if let hunks, hunks.reduce(0, { $0 + $1.lines.count }) <= Self.maxCachedDiffLines {
                diffCache.insert(hunks, for: key)
            }
            diff = (commit.hash, file.path, hunks ?? [])
        }
    }

    func loadFullMessage() {
        guard !suspended, let commit else { return }
        messageTask?.cancel()
        let token = UUID()
        messageGeneration = token
        isLoadingFullMessage = true
        messageTask = Task { [self] in
            let message = await GitStatusService.shared.fullCommitMessage(for: commit.hash, in: repositoryURL)
            guard !Task.isCancelled, !suspended, messageGeneration == token,
                  self.commit?.hash == commit.hash else { return }
            fullMessage = message
            isLoadingFullMessage = false
            messageTask = nil
        }
    }

}
