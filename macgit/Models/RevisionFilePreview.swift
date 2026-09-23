// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct RevisionFilePreview: Sendable {
    let text: String?
    let lines: [DiffLine]
    let message: String?
    var imageData: Data? = nil

    static func notice(_ message: String) -> Self {
        Self(text: nil, lines: [], message: message)
    }
}
