// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Core Graphics counterpart of BranchGraphRowCanvas for native table cells.
enum CommitGraphRowRenderer {
    static let rowHeight: CGFloat = 24
    static let laneWidth: CGFloat = 14
    static let dotSize: CGFloat = 8

    static func draw(
        _ geometry: CommitGraphRowGeometry,
        rowIndex: Int,
        in context: CGContext,
        dotBackground: NSColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(2.2)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // The geometry cache has already translated strokes into row coordinates.
        // Dots retain their graph coordinates and need the row offset below.
        for stroke in geometry.strokes {
            context.setStrokeColor(BranchGraphCanvas.lineNSColor(
                colorIndex: stroke.colorIndex,
                isHighlighted: stroke.isHighlighted
            ).cgColor)
            context.addPath(stroke.path.cgPath)
            context.strokePath()
        }

        for dot in geometry.dots {
            let center = BranchGraphCanvas.position(
                for: dot.center,
                rowHeight: rowHeight,
                laneWidth: laneWidth,
                rowOffset: Double(rowIndex)
            )
            let color = BranchGraphCanvas.lineNSColor(
                colorIndex: dot.colorIndex,
                isHighlighted: dot.isHighlighted
            ).cgColor
            let outerPath = BranchGraphCanvas.dotPath(
                for: dot,
                rowHeight: rowHeight,
                laneWidth: laneWidth,
                dotSize: dotSize,
                rowOffset: Double(rowIndex)
            ).cgPath
            context.setFillColor(color)
            switch dot.type {
            case .default:
                context.addPath(outerPath)
                context.fillPath()
                context.setStrokeColor(dotBackground.cgColor)
                context.setLineWidth(1.5)
                context.addPath(outerPath)
                context.strokePath()
            case .head:
                context.setFillColor(dotBackground.cgColor)
                context.addPath(outerPath)
                context.fillPath()
                context.setStrokeColor(color)
                context.setLineWidth(2)
                context.addPath(outerPath)
                context.strokePath()
                let innerSize = dotSize - 2
                context.setFillColor(color)
                context.fillEllipse(in: CGRect(
                    x: center.x - innerSize / 2,
                    y: center.y - innerSize / 2,
                    width: innerSize,
                    height: innerSize
                ))
            case .merge:
                context.addPath(outerPath)
                context.fillPath()
                context.setStrokeColor(dotBackground.cgColor)
                context.setLineWidth(2)
                // GraphicsContext's default dot stroke has butt caps and miter joins.
                context.setLineCap(.butt)
                context.setLineJoin(.miter)
                context.move(to: CGPoint(x: center.x, y: center.y - 3))
                context.addLine(to: CGPoint(x: center.x, y: center.y + 3))
                context.strokePath()
                context.move(to: CGPoint(x: center.x - 3, y: center.y))
                context.addLine(to: CGPoint(x: center.x + 3, y: center.y))
                context.strokePath()
            }
        }
    }
}
