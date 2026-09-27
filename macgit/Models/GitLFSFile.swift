// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSFile: Decodable, Identifiable, Sendable {
    let name: String
    let size: Int64
    let checkout: Bool
    let downloaded: Bool
    let oid: String
    var modification: String? = nil
    var id: String { name }
    var localState: String { modification ?? (checkout ? "Available" : downloaded ? "Cached · Restore Content" : "Not downloaded") }
}
