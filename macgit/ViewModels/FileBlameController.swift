// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

/// Backs the Blame window: blame of one file at a revision, plus the file's
/// history so the user can step to older or newer revisions.
@MainActor @Observable
final class FileBlameController {
    /// Consecutive lines last changed by the same commit.
    struct Group: Identifiable, Equatable {
        let lines: Range<Int>
        let hash: String
        var id: Int { lines.lowerBound }
    }

    static let lineLimit = 50_000

    let repositoryURL: URL
    let initialPath: String
    let initialRevision: String
    private(set) var path: String
    private(set) var revision: String
    private(set) var history: [FileHistoryEntry] = []
    private(set) var commits: [String: FileBlameCommit] = [:]
    private(set) var lines: [DiffLine] = []
    private(set) var groups: [Group] = []
    /// Index into `groups` for every line, so the gutter can find visible groups without searching.
    private(set) var groupIndexByLine: [Int] = []
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private var blameTask: Task<Void, Never>?

    init(repositoryURL: URL, path: String, revision: String) {
        self.repositoryURL = repositoryURL
        initialPath = path
        initialRevision = revision
        self.path = path
        self.revision = revision
    }

    var historyIndex: Int? { history.firstIndex { $0.commit.hash == revision } }
    var olderEntry: FileHistoryEntry? {
        guard let index = historyIndex else { return revision == initialRevision ? history.first : nil }
        return history.indices.contains(index + 1) ? history[index + 1] : nil
    }
    var newerEntry: FileHistoryEntry? {
        guard let index = historyIndex, index > 0 else { return nil }
        return history[index - 1]
    }

    /// Groups with at least one line inside the viewport described by a scroll offset and height.
    func visibleGroups(offset: CGFloat, height: CGFloat, rowHeight: CGFloat) -> ArraySlice<Group> {
        let firstLine = max(0, Int(floor(offset / rowHeight)))
        guard firstLine < groupIndexByLine.count else { return [] }
        let lastLine = min(groupIndexByLine.count - 1, firstLine + Int(ceil(max(0, height) / rowHeight)) + 1)
        return groups[groupIndexByLine[firstLine]...groupIndexByLine[lastLine]]
    }

    func load() {
        historyTask?.cancel()
        historyTask = Task { [weak self] in
            guard let self else { return }
            let loaded = try? await GitStatusService.shared.fileHistory(path: initialPath, revision: initialRevision, in: repositoryURL)
            guard !Task.isCancelled else { return }
            history = loaded ?? []
        }
        loadBlame()
    }

    func show(_ entry: FileHistoryEntry) {
        guard entry.commit.hash != revision || entry.path != path else { return }
        revision = entry.commit.hash
        path = entry.path
        loadBlame()
    }

    func showInitialRevision() {
        guard revision != initialRevision || path != initialPath else { return }
        revision = initialRevision
        path = initialPath
        loadBlame()
    }

    func cancel() {
        historyTask?.cancel()
        blameTask?.cancel()
        isLoading = false
    }

    private func loadBlame() {
        blameTask?.cancel()
        isLoading = true
        error = nil
        let revision = revision, path = path
        blameTask = Task { [weak self] in
            guard let self else { return }
            do {
                let blame = try await GitStatusService.shared.fileBlame(path: path, revision: revision, in: repositoryURL)
                guard !Task.isCancelled, self.revision == revision, self.path == path else { return }
                guard blame.lines.count <= Self.lineLimit else {
                    throw GitError.commandFailed("This file has too many lines to blame here.")
                }
                apply(blame)
                isLoading = false
            } catch {
                guard !Task.isCancelled, self.revision == revision, self.path == path else { return }
                apply(FileBlame(lines: [], commits: [:]))
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func apply(_ blame: FileBlame) {
        var groups: [Group] = []
        var indexes: [Int] = []
        indexes.reserveCapacity(blame.lines.count)
        var start = 0
        for (index, line) in blame.lines.enumerated() {
            if index > 0, line.hash != blame.lines[index - 1].hash {
                groups.append(Group(lines: start..<index, hash: blame.lines[start].hash))
                start = index
            }
            indexes.append(groups.count)
        }
        if !blame.lines.isEmpty {
            groups.append(Group(lines: start..<blame.lines.count, hash: blame.lines[start].hash))
        }
        commits = blame.commits
        lines = blame.lines.map {
            DiffLine(oldLineNumber: nil, newLineNumber: $0.lineNumber, text: $0.text, type: .context)
        }
        self.groups = groups
        groupIndexByLine = indexes
    }
}
