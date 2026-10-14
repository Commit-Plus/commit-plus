// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum GitFlowRoleDisplayMode: String, Codable, CaseIterable, Identifiable {
    case full
    case initial
    case hidden

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .full: "Full name"
        case .initial: "First letter"
        case .hidden: "Hidden"
        }
    }
}
