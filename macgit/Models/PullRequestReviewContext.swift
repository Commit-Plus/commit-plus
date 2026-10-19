// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct PullRequestReviewContext: Equatable, Codable {
    let path: String
    let diffHunk: String?
    let line: Int?
    let startLine: Int?
    let side: String?
    let isOutdated: Bool
}
