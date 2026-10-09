//
//  BranchGraphCanvas.swift
//  macgit
//

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

struct BranchGraphCanvas: View {
    let model: CommitGraphModel

    let rowHeight: CGFloat = 24
    let laneWidth: CGFloat = 14
    let dotSize: CGFloat = 8
    let graphTrailingPadding: CGFloat = 4

    init(model: CommitGraphModel) {
        self.model = model
    }

    var body: some View {
        Canvas { context, _ in
            drawGraph(in: &context)
        }
        .frame(
            width: graphWidth,
            height: CGFloat(model.dots.count) * rowHeight
        )
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var graphWidth: CGFloat {
        CGFloat(model.laneCount) * laneWidth + graphTrailingPadding
    }

    private func drawGraph(in context: inout GraphicsContext) {
        let strokeStyle = StrokeStyle(
            lineWidth: 2.2,
            lineCap: .round,
            lineJoin: .round
        )

        for graphPath in model.paths {
            context.stroke(
                Self.path(
                    for: graphPath,
                    rowHeight: rowHeight,
                    laneWidth: laneWidth,
                    rowOffset: 0
                ),
                with: .color(Self.lineColor(
                    colorIndex: graphPath.colorIndex,
                    isHighlighted: graphPath.isHighlighted
                )),
                style: strokeStyle
            )
        }

        for link in model.links {
            context.stroke(
                Self.linkPath(
                    for: link,
                    rowHeight: rowHeight,
                    laneWidth: laneWidth,
                    rowOffset: 0,
                    canvasWidth: graphWidth
                ),
                with: .color(Self.lineColor(
                    colorIndex: link.colorIndex,
                    isHighlighted: link.isHighlighted
                )),
                style: strokeStyle
            )
        }

        for dot in model.dots {
            Self.drawDot(
                dot,
                in: &context,
                rowHeight: rowHeight,
                laneWidth: laneWidth,
                dotSize: dotSize,
                rowOffset: 0,
                background: Color(nsColor: .windowBackgroundColor)
            )
        }
    }

    static func lineNSColor(colorIndex: Int, isHighlighted: Bool) -> NSColor {
        isHighlighted
            ? GraphPalette.nsColor(for: colorIndex)
            : NSColor(Color.gray).withAlphaComponent(0.4)
    }

    static func lineColor(colorIndex: Int, isHighlighted: Bool) -> Color {
        isHighlighted
            ? GraphPalette.color(for: colorIndex)
            : Color.gray.opacity(0.4)
    }

    static func drawDot(
        _ dot: GraphDot,
        in context: inout GraphicsContext,
        rowHeight: CGFloat,
        laneWidth: CGFloat,
        dotSize: CGFloat,
        rowOffset: Double,
        background: Color
    ) {
        let center = Self.position(
            for: dot.center,
            rowHeight: rowHeight,
            laneWidth: laneWidth,
            rowOffset: rowOffset
        )
        let color = lineColor(
            colorIndex: dot.colorIndex,
            isHighlighted: dot.isHighlighted
        )
        let outerPath = Self.dotPath(
            for: dot,
            rowHeight: rowHeight,
            laneWidth: laneWidth,
            dotSize: dotSize,
            rowOffset: rowOffset
        )

        switch dot.type {
        case .default:
            context.fill(outerPath, with: .color(color))
            context.stroke(outerPath, with: .color(background), lineWidth: 1.5)

        case .head:
            context.fill(outerPath, with: .color(background))
            context.stroke(outerPath, with: .color(color), lineWidth: 2)

            let innerSize = dotSize - 2
            let innerRect = CGRect(
                x: center.x - innerSize / 2,
                y: center.y - innerSize / 2,
                width: innerSize,
                height: innerSize
            )
            context.fill(Path(ellipseIn: innerRect), with: .color(color))

        case .merge:
            context.fill(outerPath, with: .color(color))

            let plusRadius: CGFloat = 3
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: center.y - plusRadius))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + plusRadius))
                },
                with: .color(background),
                lineWidth: 2
            )
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: center.x - plusRadius, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + plusRadius, y: center.y))
                },
                with: .color(background),
                lineWidth: 2
            )
        }
    }

    static func path(
        for graphPath: GraphPath,
        rowHeight: CGFloat,
        laneWidth: CGFloat,
        rowOffset: Double = 0,
        visibleRows: Range<Double>? = nil
    ) -> Path {
        var path = Path()
        let points = graphPath.points
        guard points.count > 1 else { return path }
        let segments = visibleRows.map { graphPath.segmentEndIndices(intersecting: $0) }
            ?? 1..<points.count
        guard !segments.isEmpty else { return path }

        var last = position(
            for: points[segments.lowerBound - 1],
            rowHeight: rowHeight,
            laneWidth: laneWidth,
            rowOffset: rowOffset
        )
        path.move(to: last)

        for index in segments {
            let current = position(
                for: points[index],
                rowHeight: rowHeight,
                laneWidth: laneWidth,
                rowOffset: rowOffset
            )

            if current.x > last.x {
                addRoundedRoute([last, CGPoint(x: current.x, y: last.y), current],
                                radius: laneWidth, to: &path)
            } else if current.x < last.x {
                if index < points.count - 1 {
                    let middleY = (last.y + current.y) / 2
                    addRoundedRoute([last, CGPoint(x: last.x, y: middleY),
                                     CGPoint(x: current.x, y: middleY), current],
                                    radius: laneWidth, to: &path)
                } else {
                    addRoundedRoute([last, CGPoint(x: last.x, y: current.y), current],
                                    radius: laneWidth, to: &path)
                }
            } else {
                path.addLine(to: current)
            }

            last = current
        }

        return path
    }

    static func linkPath(
        for link: GraphLink,
        rowHeight: CGFloat,
        laneWidth: CGFloat,
        rowOffset: Double = 0,
        canvasWidth: CGFloat? = nil
    ) -> Path {
        var path = Path()
        path.move(to: position(
            for: link.start,
            rowHeight: rowHeight,
            laneWidth: laneWidth,
            rowOffset: rowOffset
        ))
        let start = position(for: link.start, rowHeight: rowHeight, laneWidth: laneWidth, rowOffset: rowOffset)
        let end = position(for: link.end, rowHeight: rowHeight, laneWidth: laneWidth, rowOffset: rowOffset)
        if end.x < start.x {
            // A parent already running in a left lane loops around the merge
            // lane on the right, then returns horizontally into that parent.
            // Leave room for half the 2.2-point stroke at the canvas edge.
            let outerX = min(start.x + laneWidth * 1.6, canvasWidth.map { max(0, $0 - 1.1) } ?? .greatestFiniteMagnitude)
            addRoundedRoute([start, CGPoint(x: outerX, y: start.y),
                             CGPoint(x: outerX, y: end.y), end],
                            radius: laneWidth, to: &path)
        } else {
            addRoundedRoute([start, CGPoint(x: end.x, y: start.y), end],
                            radius: laneWidth, to: &path)
        }
        return path
    }

    /// Straight orthogonal runs joined by circular quarter-turns.
    private static func addRoundedRoute(_ points: [CGPoint], radius: CGFloat, to path: inout Path) {
        let circleControl: CGFloat = 0.5522847498
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let corner = points[index]
            let next = points[index + 1]
            let incoming = hypot(corner.x - previous.x, corner.y - previous.y)
            let outgoing = hypot(next.x - corner.x, next.y - corner.y)
            guard incoming > 0, outgoing > 0 else {
                path.addLine(to: corner)
                continue
            }
            // Two adjacent corners share a segment without overlapping arcs.
            let r = min(radius, incoming / (index > 1 ? 2 : 1),
                        outgoing / (index < points.count - 2 ? 2 : 1))
            let inX = (corner.x - previous.x) / incoming
            let inY = (corner.y - previous.y) / incoming
            let outX = (next.x - corner.x) / outgoing
            let outY = (next.y - corner.y) / outgoing
            let entry = CGPoint(x: corner.x - inX * r, y: corner.y - inY * r)
            let exit = CGPoint(x: corner.x + outX * r, y: corner.y + outY * r)
            path.addLine(to: entry)
            path.addCurve(to: exit,
                          control1: CGPoint(x: entry.x + inX * r * circleControl,
                                            y: entry.y + inY * r * circleControl),
                          control2: CGPoint(x: exit.x - outX * r * circleControl,
                                            y: exit.y - outY * r * circleControl))
        }
        if let end = points.last { path.addLine(to: end) }
    }

    static func dotPath(
        for dot: GraphDot,
        rowHeight: CGFloat,
        laneWidth: CGFloat,
        dotSize: CGFloat,
        rowOffset: Double = 0
    ) -> Path {
        let center = position(
            for: dot.center,
            rowHeight: rowHeight,
            laneWidth: laneWidth,
            rowOffset: rowOffset
        )
        let size = dot.type == .default ? dotSize : dotSize + 4
        return Path(ellipseIn: CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        ))
    }

    static func position(
        for point: CGPoint,
        rowHeight: CGFloat,
        laneWidth: CGFloat,
        rowOffset: Double = 0
    ) -> CGPoint {
        CGPoint(
            x: CGFloat((point.x - 10) / 12) * laneWidth + laneWidth / 2,
            y: CGFloat(point.y - rowOffset) * rowHeight
        )
    }
}
