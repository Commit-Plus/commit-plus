// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSCandidate: Identifiable, Sendable {
    let path: String
    let size: Int64
    var id: String { path }
}
