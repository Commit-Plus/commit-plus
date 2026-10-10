// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated struct DiffTextFingerprint: Hashable, Sendable {
    let text: String
    private let precomputedHash: Int

    init(_ text: String) {
        self.text = text
        precomputedHash = text.hashValue
    }

    init(text: String, precomputedHash: Int) {
        self.text = text
        self.precomputedHash = precomputedHash
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(precomputedHash)
        hasher.combine(text)
    }
}
