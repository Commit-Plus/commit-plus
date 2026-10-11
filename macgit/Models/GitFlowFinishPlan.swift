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

import Foundation

final class GitFlowFinishPlan: Identifiable, Codable, Equatable, Sendable {
    let kind: GitFlowTopicKind
    let sourceBranch: String
    let primaryTargetBranch: String
    let secondaryTargetBranch: String?
    let tagName: String?
    let createTag: Bool
    let deleteSourceBranch: Bool
    let worktreePath: URL?
    let removeWorktree: Bool
    let strategy: GitFlowTopicFinishStrategy

    var id: String { "\(kind.rawValue):\(sourceBranch)" }

    var targetBranch: String { primaryTargetBranch }

    var targetBranches: [String] {
        if let secondaryTargetBranch {
            return [primaryTargetBranch, secondaryTargetBranch]
        }
        return [primaryTargetBranch]
    }

    init(
        kind: GitFlowTopicKind,
        sourceBranch: String,
        targetBranch: String,
        secondaryTargetBranch: String? = nil,
        tagName: String? = nil,
        createTag: Bool = false,
        deleteSourceBranch: Bool,
        worktreePath: URL? = nil,
        removeWorktree: Bool = false,
        strategy: GitFlowTopicFinishStrategy = .mergeNoFastForward
    ) {
        self.worktreePath = worktreePath
        self.removeWorktree = removeWorktree
        self.kind = kind
        self.sourceBranch = sourceBranch
        self.primaryTargetBranch = targetBranch
        self.secondaryTargetBranch = secondaryTargetBranch
        self.tagName = tagName
        self.createTag = createTag
        self.deleteSourceBranch = deleteSourceBranch
        self.strategy = kind.requiresReleaseTag ? .mergeNoFastForward : strategy
    }

    static func == (lhs: GitFlowFinishPlan, rhs: GitFlowFinishPlan) -> Bool {
        lhs.kind == rhs.kind
            && lhs.sourceBranch == rhs.sourceBranch
            && lhs.primaryTargetBranch == rhs.primaryTargetBranch
            && lhs.secondaryTargetBranch == rhs.secondaryTargetBranch
            && lhs.tagName == rhs.tagName
            && lhs.createTag == rhs.createTag
            && lhs.deleteSourceBranch == rhs.deleteSourceBranch
            && lhs.worktreePath == rhs.worktreePath
            && lhs.removeWorktree == rhs.removeWorktree
            && lhs.strategy == rhs.strategy
    }

    func normalizedForExecution() -> GitFlowFinishPlan {
        GitFlowFinishPlan(
            kind: kind,
            sourceBranch: sourceBranch,
            targetBranch: primaryTargetBranch,
            secondaryTargetBranch: secondaryTargetBranch,
            tagName: createTag
                ? tagName?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            createTag: createTag,
            deleteSourceBranch: deleteSourceBranch,
            worktreePath: worktreePath,
            removeWorktree: removeWorktree,
            strategy: strategy
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind, sourceBranch, primaryTargetBranch, secondaryTargetBranch
        case tagName, createTag, deleteSourceBranch, strategy, worktreePath, removeWorktree
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        worktreePath = try container.decodeIfPresent(URL.self, forKey: .worktreePath)
        removeWorktree = try container.decodeIfPresent(Bool.self, forKey: .removeWorktree) ?? false
        kind = try container.decode(GitFlowTopicKind.self, forKey: .kind)
        sourceBranch = try container.decode(String.self, forKey: .sourceBranch)
        primaryTargetBranch = try container.decode(String.self, forKey: .primaryTargetBranch)
        secondaryTargetBranch = try container.decodeIfPresent(String.self, forKey: .secondaryTargetBranch)
        tagName = try container.decodeIfPresent(String.self, forKey: .tagName)
        createTag = try container.decodeIfPresent(Bool.self, forKey: .createTag) ?? false
        deleteSourceBranch = try container.decodeIfPresent(Bool.self, forKey: .deleteSourceBranch) ?? true
        let decodedStrategy = try container.decodeIfPresent(
            GitFlowTopicFinishStrategy.self,
            forKey: .strategy
        ) ?? .mergeNoFastForward
        strategy = kind.requiresReleaseTag ? .mergeNoFastForward : decodedStrategy
    }
}

struct GitFlowFinishResult: Equatable {
    let plan: GitFlowFinishPlan
    let sourceTip: String
    let targetResults: [GitFlowFinishTargetResult]
    let createdTagName: String?
    let didDeleteSourceBranch: Bool
    let deletionWarning: String?
    let rewrittenSourceTip: String?

    var targetTipBeforeMerge: String {
        targetResults.first?.tipBeforeMerge ?? ""
    }

    var targetTipAfterMerge: String {
        targetResults.first?.tipAfterMerge ?? ""
    }
}

struct GitFlowFinishTargetResult: Codable, Equatable {
    let branch: String
    let tipBeforeMerge: String
    let tipAfterMerge: String
}
