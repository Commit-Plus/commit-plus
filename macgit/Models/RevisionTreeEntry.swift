// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct RevisionTreeEntry: Identifiable, Equatable, Sendable {
    let path: String
    let objectID: String
    let mode: String
    let objectType: String
    let size: Int?
    var id: String { path }
    var name: String { String(path.split(separator: "/").last ?? "") }
    var isDirectory: Bool { objectType == "tree" }
    var isSymlink: Bool { mode == "120000" }
    var isSubmodule: Bool { mode == "160000" }
}
