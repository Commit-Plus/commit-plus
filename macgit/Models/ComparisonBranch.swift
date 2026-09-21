// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct ComparisonBranch: Identifiable, Hashable, Sendable {
    let ref: String
    var id: String { ref }
    var isRemote: Bool { ref.hasPrefix("refs/remotes/") }
    var name: String {
        String(ref.dropFirst(isRemote ? "refs/remotes/".count : "refs/heads/".count))
    }
    var label: String { "\(name) (\(isRemote ? "remote" : "local"))" }
}
