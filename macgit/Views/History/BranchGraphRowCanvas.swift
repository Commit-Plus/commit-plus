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

struct BranchGraphRowCanvas: View, Equatable {
    static let rowHeight: CGFloat = 24
    static let laneWidth: CGFloat = 14
    static let dotSize: CGFloat = 8
    static let trailingPadding: CGFloat = 4

    private let model: CommitGraphModel
    private let geometry: CommitGraphRowGeometry
    let rowIndex: Int
    @Environment(\.backgroundProminence) private var backgroundProminence

    init(model: CommitGraphModel, rowIndex: Int) {
        self.model = model
        self.rowIndex = rowIndex
        geometry = model.rowGeometryCache.geometry(for: model, rowIndex: rowIndex)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rowIndex == rhs.rowIndex && (
            lhs.geometry === rhs.geometry ||
            (lhs.geometry.strokes == rhs.geometry.strokes && lhs.geometry.dots == rhs.geometry.dots)
        )
    }

    var body: some View {
        Canvas { context, size in
            // Keep dense graphs inside their column while retaining the native
            // lane spacing and the full row height for continuous vertical lines.
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            drawRow(in: &context, canvasWidth: size.width)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.rowHeight)
        // A small native Table row proposes 16 pt of cell content with 4 pt
        // vertical insets. Extending the canvas through those insets makes the
        // graph join exactly at adjacent row boundaries.
        .padding(.vertical, -4)
        .accessibilityHidden(true)
    }

    private func drawRow(in context: inout GraphicsContext, canvasWidth: CGFloat) {
        let geometry = model.rowGeometryCache.geometry(for: model, rowIndex: rowIndex, canvasWidth: canvasWidth)
        let strokeStyle = StrokeStyle(
            lineWidth: 2.2,
            lineCap: .round,
            lineJoin: .round
        )
        let rowOffset = Double(rowIndex)

        for stroke in geometry.strokes {
            context.stroke(
                stroke.path,
                with: .color(BranchGraphCanvas.lineColor(
                    colorIndex: stroke.colorIndex,
                    isHighlighted: stroke.isHighlighted
                )),
                style: strokeStyle
            )
        }

        for dot in geometry.dots {
            BranchGraphCanvas.drawDot(
                dot,
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
