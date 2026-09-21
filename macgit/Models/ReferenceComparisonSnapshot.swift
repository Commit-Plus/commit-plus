// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct ReferenceComparisonSnapshot: Sendable {
    let base: String
    let target: String
    let mergeBases: [String]
    let baseOnlyCount: Int
    let targetOnlyCount: Int

    func diffBase(for mode: ReferenceComparisonMode) throws -> String {
        if mode == .tips { return base }
        guard mergeBases.count == 1, let mergeBase = mergeBases.first else {
            throw GitError.commandFailed(mergeBases.isEmpty
                ? "These branches have no common ancestor. Select Tip-to-tip to compare their trees."
                : "These branches have multiple merge bases. Select Tip-to-tip to compare their trees.")
        }
        return mergeBase
    }
}
