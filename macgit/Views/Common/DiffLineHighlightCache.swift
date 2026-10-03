// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

@MainActor
final class DiffLineHighlightCache {
    private var entries: [UUID: AttributedString] = [:]
    private var insertionOrder: [UUID] = []
    private let capacity: Int

    init(capacity: Int = 512) {
        self.capacity = capacity
    }

    func cachedText(for lineID: UUID) -> AttributedString? {
        entries[lineID]
    }

    func text(for line: DiffLine, fileExtension: String, fontSize: CGFloat = 12) -> AttributedString {
        if let cached = entries[line.id] { return cached }

        let highlighted = SyntaxHighlighter(fileExtension: fileExtension)
            .attributedString(for: line.text, fontSize: fontSize)
        if insertionOrder.count == capacity, let oldestLineID = insertionOrder.first {
            entries.removeValue(forKey: oldestLineID)
            insertionOrder.removeFirst()
        }
        entries[line.id] = highlighted
        insertionOrder.append(line.id)
        return highlighted
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
    }
}
