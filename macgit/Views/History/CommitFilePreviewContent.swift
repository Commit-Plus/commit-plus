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
import SwiftUI

/// Uses fixed-height rows so two-axis scrolling never needs to lay out the full file.
struct CommitFilePreviewContent: View {
    let lines: [DiffLine]
    let fileExtension: String
    @State private var visibleRange = 0..<0
    @State private var contentWidth: CGFloat = 0
    @State private var highlightCache = CommitFilePreviewHighlightCache()

    private let rowHeight = CommitFilePreviewViewport.rowHeight

    var body: some View {
        GeometryReader { geometry in
            let range = visibleRange.isEmpty
                ? CommitFilePreviewViewport.rows(offset: 0, height: geometry.size.height, count: lines.count)
                : visibleRange
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: CGFloat(range.lowerBound) * rowHeight)
                    ForEach(range, id: \.self) { index in
                        let line = lines[index]
                        DiffLineView(
                            line: line,
                            fileExtension: fileExtension,
                            isSelected: false,
                            cachedHighlightedText: highlightCache.text(for: line, fileExtension: fileExtension)
                        )
                        .frame(height: rowHeight)
                        .textSelection(.enabled)
                    }
                    Color.clear.frame(height: CGFloat(lines.count - range.upperBound) * rowHeight)
                }
                .frame(width: max(geometry.size.width, contentWidth), alignment: .topLeading)
            }
            .defaultScrollAnchor(.topLeading)
            .onScrollGeometryChange(for: Range<Int>.self) { scroll in
                CommitFilePreviewViewport.rows(
                    offset: scroll.contentOffset.y,
                    height: scroll.containerSize.height,
                    count: lines.count
                )
            } action: { _, range in
                visibleRange = range
            }
        }
        .background(.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .padding(12)
        .task {
            // Measure plain text only; regex highlighting is reserved for visible rows.
            // Yield between batches so opening a large file does not block the sheet.
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ]
            var width: CGFloat = 0
            for (index, line) in lines.enumerated() {
                guard !Task.isCancelled else { return }
                width = max(width, (line.text as NSString).size(withAttributes: attributes).width)
                if index.isMultiple(of: 128) { await Task.yield() }
            }
            contentWidth = ceil(width) + 130
        }
    }
}
