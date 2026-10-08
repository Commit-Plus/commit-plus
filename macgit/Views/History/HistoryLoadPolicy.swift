// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Shared loading and selection decisions, independent of the History UI.
enum HistoryLoadPolicy {
    enum Scope {
        case allBranches
        case currentBranch
        case ref(String)
    }

    static func historyScope(branchFilter: HistoryBranchFilter) -> Scope {
        switch branchFilter {
        case .all:
            return .allBranches
        case .current:
            return .currentBranch
        case .branch(let branch):
            return .ref(branch)
        }
    }

    static func reloadTargetHash(
        reset: Bool,
        selectedCommitHash: String?,
        newScrollTarget: String?
    ) -> String? {
        reset ? (newScrollTarget ?? selectedCommitHash) : selectedCommitHash
    }

    static func highlighting(
        for branchFilter: HistoryBranchFilter
    ) -> CommitGraphHighlighting {
        branchFilter == .all ? .all : .currentBranchOnly
    }

    static func highlightRootHash(
        for branchFilter: HistoryBranchFilter,
        commits: [Commit],
        repositoryURL: URL
    ) async -> String? {
        switch branchFilter {
        case .all:
            return nil
        case .current:
            if let decoratedHead = resolvedHeadHash(from: commits) {
                return decoratedHead
            }
            return await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        case .branch(let branch):
            if let tipCommit = commits.first {
                return tipCommit.hash
            }
            return await GitStatusService.shared.tipHash(for: branch, in: repositoryURL)
        }
    }

    static func primaryHashForTableSelection(
        oldSelection: Set<String>,
        newSelection: Set<String>,
        previousPrimaryHash: String?,
        visibleHashes: [String]
    ) -> String? {
        guard !newSelection.isEmpty else { return nil }

        let addedHashes = newSelection.subtracting(oldSelection)
        if addedHashes.count == 1 {
            return addedHashes.first
        }

        let indexByHash = Dictionary(
            uniqueKeysWithValues: visibleHashes.enumerated().map { ($0.element, $0.offset) }
        )
        if addedHashes.count > 1,
           let previousPrimaryHash,
           let previousIndex = indexByHash[previousPrimaryHash] {
            return addedHashes.max { lhs, rhs in
                abs((indexByHash[lhs] ?? previousIndex) - previousIndex)
                    < abs((indexByHash[rhs] ?? previousIndex) - previousIndex)
            }
        }

        if let previousPrimaryHash,
           newSelection.contains(previousPrimaryHash) {
            return previousPrimaryHash
        }

        return visibleHashes.last(where: newSelection.contains)
    }

    static func normalizedSearchQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return "" }
        return trimmed
    }

    static func resolvedHeadHash(from commits: [Commit]) -> String? {
        commits.first(where: { commit in
            commit.refs.contains {
                $0 == "HEAD" || $0.hasPrefix("HEAD -> ")
            }
        })?.hash
    }

    static func tipCommit(for branch: String, in commits: [Commit]) -> Commit? {
        commits.first { commit in
            commit.refs.contains { ref in
                ref == branch || ref == "HEAD -> \(branch)"
            }
        }
    }

    static func commit(withHash hash: String?, in commits: [Commit]) -> Commit? {
        guard let hash else { return nil }
        return commits.first { $0.hash == hash }
    }

    static func cherryPickCommits(from contextMenuCommits: [Commit]) -> [Commit] {
        Array(contextMenuCommits.reversed())
    }

    static func draggedCommits(
        startingAt hash: String,
        commits: [Commit],
        selection: HistoryCommitSelection
    ) -> [GitDraggedCommit] {
        let commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0) })
        return selection
            .draggedHashes(startingAt: hash, visibleHashes: commits.map(\.hash))
            .compactMap { selectedHash in
                guard let commit = commitsByHash[selectedHash] else { return nil }
                return GitDraggedCommit(
                    hash: commit.hash,
                    message: commit.message,
                    isMerge: commit.isMerge
                )
            }
    }

    static func canSquashCommits(
        _ selectedCommits: [Commit],
        selectedHashes: [String],
        headHash: String?
    ) -> Bool {
        guard selectedCommits.count >= 2,
              selectedCommits.count == selectedHashes.count,
              selectedCommits.first?.hash == headHash,
              selectedCommits.allSatisfy({ !$0.isMerge }) else {
            return false
        }

        return zip(selectedCommits, selectedCommits.dropFirst()).allSatisfy { newer, older in
            newer.parents.first == older.hash
        }
    }

    static func loadKey(
        filter: HistoryBranchFilter,
        searchQuery: String,
        pageSize: Int,
        onlyThisBranch: Bool,
        baseBranch: String?
    ) -> String {
        let comparison = onlyThisBranch && filter != .all
            ? "only:\(baseBranch ?? "")" : "full"
        return "\(filter.storageValue)|\(searchQuery)|\(pageSize)|\(comparison)"
    }

    static func emptyDetail(
        onlyThisBranch: Bool,
        filter: HistoryBranchFilter,
        baseBranch: String?,
        searchQuery: String
    ) -> String {
        if onlyThisBranch && filter != .all {
            guard let baseBranch else { return "Choose a base branch to compare against" }
            return searchQuery.isEmpty
                ? "No commits ahead of \(baseBranch)"
                : "No matching commits ahead of \(baseBranch). Try author name, email, or commit ID"
        }
        return searchQuery.isEmpty
            ? "Repository may be empty" : "Try author name, email, or commit ID"
    }
}
