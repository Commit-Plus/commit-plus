// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated struct DiffContentRevision: Hashable, Sendable {
    struct Line: Hashable, Sendable {
        let oldLineNumber: Int?
        let newLineNumber: Int?
        let text: String
        let type: DiffLineType
    }

    let header: String
    let lines: [Line]
}
