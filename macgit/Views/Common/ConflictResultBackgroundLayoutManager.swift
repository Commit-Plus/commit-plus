//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import AppKit

final class ConflictResultBackgroundLayoutManager: NSLayoutManager {
    var changedLineIndices: Set<Int> = []
    var blankLineIndices: Set<Int> = []
    var viewportWidth: CGFloat = 0
    var lineStartOffsets: [Int] = [0]

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        let text = textStorage.string as NSString
        let backgroundWidth = max(viewportWidth, usedRect(for: textContainer).width)
        var visibleLineIndex: Int?
        enumerateLineFragments(forGlyphRange: glyphsToShow) { [self] rect, _, _, glyphRange, _ in
            let lineIndex: Int
            if let visibleLineIndex {
                lineIndex = visibleLineIndex
            } else {
                let characterIndex = characterIndexForGlyph(at: glyphRange.location)
                var lower = 0
                var upper = lineStartOffsets.count
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if lineStartOffsets[middle] <= min(characterIndex, text.length) {
                        lower = middle + 1
                    } else {
                        upper = middle
                    }
                }
                lineIndex = max(0, lower - 1)
            }
            visibleLineIndex = lineIndex + 1

            let backgroundRect = NSRect(
                x: origin.x,
                y: origin.y + rect.minY,
                width: backgroundWidth,
                height: rect.height
            )

            if blankLineIndices.contains(lineIndex) {
                drawPlaceholderBackground(in: backgroundRect)
            } else if changedLineIndices.contains(lineIndex) {
                NSColor.systemGreen.withAlphaComponent(0.13).setFill()
                backgroundRect.fill()
            }
        }

        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawPlaceholderBackground(in rect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.08).setFill()
        rect.fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let hatch = NSBezierPath()
        hatch.lineWidth = 0.5
        NSColor.separatorColor.withAlphaComponent(0.22).setStroke()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            hatch.move(to: NSPoint(x: x, y: rect.minY))
            hatch.line(to: NSPoint(x: x + rect.height, y: rect.maxY))
            x += 8
        }
        hatch.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
