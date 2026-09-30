// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct RepoPickerStatusSnapshot: Equatable, Sendable {
    var currentBranch: String?
    var changedFileCount: Int
    var behindCount: Int
    var aheadCount: Int
    var includesAheadBehind: Bool
}
