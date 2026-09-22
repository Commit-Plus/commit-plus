// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated enum ComparisonEndpoint: Equatable, Sendable {
    case revision(String)
    case workingTree
    case index

    var label: String {
        switch self {
        case .revision(let ref): ref
        case .workingTree: "Working Tree"
        case .index: "Index (staged content)"
        }
    }
}
