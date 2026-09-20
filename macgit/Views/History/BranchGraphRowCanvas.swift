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

struct BranchGraphRowCanvas: View {
    static let rowHeight: CGFloat = 24
    static let laneWidth: CGFloat = 14
    static let dotSize: CGFloat = 8
    static let trailingPadding: CGFloat = 4

    let model: CommitGraphModel
    let rowIndex: Int
    @Environment(\.backgroundProminence) private var backgroundProminence

    var body: some View {
        Canvas { context, size in
            // Keep dense graphs inside their column while retaining the native
            // lane spacing and the full row height for continuous vertical lines.
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            drawRow(in: &context)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.rowHeight)
        // A small native Table row proposes 16 pt of cell content with 4 pt
        // vertical insets. Extending the canvas through those insets makes the
        // graph join exactly at adjacent row boundaries.
        .padding(.vertical, -4)
        .accessibilityHidden(true)
    }

    private func drawRow(in context: inout GraphicsContext) {
        guard model.rowSlices.indices.contains(rowIndex) else { return }
        let row = model.rowSlices[rowIndex]
        let strokeStyle = StrokeStyle(
            lineWidth: 2.2,
            lineCap: .round,
            lineJoin: .round
        )
        let rowOffset = Double(rowIndex)

        for pathIndex in row.pathIndices where model.paths.indices.contains(pathIndex) {
            let graphPath = model.paths[pathIndex]
            context.stroke(
                BranchGraphCanvas.path(
                    for: graphPath,
                    rowHeight: Self.rowHeight,
                    laneWidth: Self.laneWidth,
                    rowOffset: rowOffset
                ),
                with: .color(BranchGraphCanvas.lineColor(
                    colorIndex: graphPath.colorIndex,
                    isHighlighted: graphPath.isHighlighted
                )),
                style: strokeStyle
            )
        }

        for linkIndex in row.linkIndices where model.links.indices.contains(linkIndex) {
            let link = model.links[linkIndex]
            context.stroke(
                BranchGraphCanvas.linkPath(
                    for: link,
                    rowHeight: Self.rowHeight,
                    laneWidth: Self.laneWidth,
                    rowOffset: rowOffset
                ),
                with: .color(BranchGraphCanvas.lineColor(
                    colorIndex: link.colorIndex,
                    isHighlighted: link.isHighlighted
                )),
                style: strokeStyle
            )
        }

        for dotIndex in row.dotIndices where model.dots.indices.contains(dotIndex) {
            BranchGraphCanvas.drawDot(
                model.dots[dotIndex],
                in: &context,
                rowHeight: Self.rowHeight,
                laneWidth: Self.laneWidth,
                dotSize: Self.dotSize,
                rowOffset: rowOffset,
                background: dotBackground
            )
        }
    }

    private var dotBackground: Color {
        if backgroundProminence == .increased {
            return Color(nsColor: .selectedContentBackgroundColor)
        }

        let rowBackgrounds = NSColor.alternatingContentBackgroundColors
        guard !rowBackgrounds.isEmpty else {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color(nsColor: rowBackgrounds[rowIndex % rowBackgrounds.count])
    }
}
