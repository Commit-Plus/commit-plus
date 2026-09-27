// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSTrackingReview: Identifiable, Sendable {
    let id = UUID()
    let pattern: String
    let literal: Bool
    let removing: Bool
    let attributes: Data?
    let preview: String
}
