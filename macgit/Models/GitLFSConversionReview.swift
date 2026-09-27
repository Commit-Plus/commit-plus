// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSConversionReview: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let contentHash: String
    let indexEntry: String
    let attributes: String
}
