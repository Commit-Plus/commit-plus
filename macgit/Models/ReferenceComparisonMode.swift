// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated enum ReferenceComparisonMode: String, CaseIterable, Identifiable, Sendable {
    case mergeBase
    case tips

    var id: Self { self }
    var title: String {
        switch self {
        case .mergeBase: "Changes since merge base"
        case .tips: "Tip-to-tip"
        }
    }
}
