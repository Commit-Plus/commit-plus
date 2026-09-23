// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import CoreGraphics
import CoreText

/// Measures small pieces off the main actor; no text layout sees the entire line.
nonisolated struct DiffLongLineLayout: Sendable {
    static let byteThreshold = 4_096
    static let chunkSize = 512

    struct Chunk: Sendable {
        let range: Range<String.Index>
        let offset: CGFloat
        let width: CGFloat
    }

    let text: String
    let chunks: [Chunk]
    let width: CGFloat

    static func isLong(_ text: String) -> Bool {
        text.utf8.count > byteThreshold
    }

    static func prepare(text: String, fontName: String, fontSize: CGFloat = 12) -> Self? {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        var chunks: [Chunk] = []
        var start = text.startIndex
        var width: CGFloat = 0
        while start < text.endIndex {
            guard !Task.isCancelled else { return nil }
            let end = text.index(start, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: String(text[start..<end]), attributes: attributes)
            )
            let chunkWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            chunks.append(Chunk(range: start..<end, offset: width, width: chunkWidth))
            width += chunkWidth
            start = end
        }
        return Self(text: text, chunks: chunks, width: width)
    }

    func visibleChunks(in viewport: CGRect) -> Range<Int> {
        guard !chunks.isEmpty else { return 0..<0 }
        // Keep a screen of neighbours ready for smooth horizontal scrolling.
        let padding = max(512, viewport.width)
        let left = max(0, viewport.minX - padding)
        let right = viewport.maxX + padding
        func firstEnding(after position: CGFloat) -> Int {
            var lower = 0
            var upper = chunks.count
            while lower < upper {
                let middle = (lower + upper) / 2
                let chunk = chunks[middle]
                if chunk.offset + chunk.width < position {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return lower
        }
        let first = firstEnding(after: left)
        let last = min(chunks.count, firstEnding(after: right) + 1)
        return first..<max(first, last)
    }

    static func load(text: String, fontName: String) async -> Self? {
        let worker = Task.detached(priority: .userInitiated) {
            prepare(text: text, fontName: fontName)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
