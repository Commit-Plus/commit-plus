//
//  CommitGraphGenerator.swift
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
import Foundation

nonisolated enum CommitGraphGenerator {
    private static let unitWidth = 12.0
    private static let halfWidth = 6.0
    private static let unitHeight = 1.0
    private static let halfHeight = 0.5
    private static let firstLaneX = 10.0
    private static let colorCount = 10

    @concurrent
    static func generateAsync(
        commits: [Commit],
        highlighting: CommitGraphHighlighting,
        headHash: String?,
        highlightRootHash: String?
    ) async -> CommitGraphModel {
        generate(
            commits: commits,
            highlighting: highlighting,
            headHash: headHash,
            highlightRootHash: highlightRootHash
        )
    }

    static func generate(
        commits: [Commit],
        highlighting: CommitGraphHighlighting,
        headHash: String?,
        highlightRootHash: String?
    ) -> CommitGraphModel {
        guard !commits.isEmpty else {
            return CommitGraphModel(
                paths: [],
                links: [],
                dots: [],
                laneCount: 1,
                commitMetadata: [:],
                rowIndexByHash: [:]
            )
        }

        let rowByHash = Dictionary(
            uniqueKeysWithValues: commits.enumerated().map { ($0.element.hash, $0.offset) }
        )
        let highlightedCommits = reachableCommits(
            from: highlightRootHash,
            commits: commits,
            rowByHash: rowByHash
        )

        var mutablePaths: [MutableGraphPath] = []
        var links: [GraphLink] = []
        var dots: [GraphDot] = []
        var metadata: [String: GraphCommitMetadata] = [:]
        var unsolved: [PathHelper] = []
        var ended: [PathHelper] = []
        var offsetY = -halfHeight
        var colorPicker = ColorPicker(colorCount: colorCount)
        var maxLane = 0

        for commit in commits {
            var major: PathHelper?
            offsetY += unitHeight

            var offsetX = 4 - halfWidth
            let maxOffsetOld = unsolved.last?.lastX ?? offsetX + unitWidth
            var isHighlighted = false

            for path in unsolved {
                if path.next == commit.hash {
                    if major == nil {
                        offsetX += unitWidth
                        major = path
                        isHighlighted = path.isHighlighted

                        if let firstParent = commit.parents.first {
                            path.next = firstParent
                            path.go(toX: offsetX, y: offsetY, halfHeight: halfHeight)
                        } else {
                            path.end(atX: offsetX, y: offsetY, halfHeight: halfHeight)
                            ended.append(path)
                        }
                    } else if let major {
                        path.end(atX: major.lastX, y: offsetY, halfHeight: halfHeight)
                        ended.append(path)
                        isHighlighted = isHighlighted || path.isHighlighted
                    }
                } else {
                    offsetX += unitWidth
                    path.pass(x: offsetX, y: offsetY, halfHeight: halfHeight)
                }
            }

            if !ended.isEmpty {
                let endedIDs = Set(ended.map(ObjectIdentifier.init))
                for path in ended {
                    colorPicker.recycle(path.colorIndex)
                }
                unsolved.removeAll { endedIDs.contains(ObjectIdentifier($0)) }
                ended.removeAll(keepingCapacity: true)
            }

            if !isHighlighted {
                switch highlighting {
                case .all:
                    isHighlighted = true
                case .currentBranchOnly:
                    isHighlighted = highlightedCommits.contains(commit.hash)
                }
            }

            if major == nil {
                offsetX += unitWidth
                if let firstParent = commit.parents.first {
                    let path = PathHelper(
                        next: firstParent,
                        isHighlighted: isHighlighted,
                        colorIndex: colorPicker.next(),
                        start: CGPoint(x: offsetX, y: offsetY)
                    )
                    unsolved.append(path)
                    mutablePaths.append(path.path)
                    major = path
                }
            } else if let major,
                      isHighlighted,
                      !major.isHighlighted,
                      !commit.parents.isEmpty {
                let highlightedPath = major.highlight()
                mutablePaths.append(highlightedPath)
            }

            let position = CGPoint(x: major?.lastX ?? offsetX, y: offsetY)
            let dotColor = major?.colorIndex ?? 0
            let dotLane = lane(forX: position.x)
            maxLane = max(maxLane, dotLane)

            let dotType: GraphDotType
            if commit.hash == headHash || commit.refs.contains(where: {
                $0 == "HEAD" || $0.hasPrefix("HEAD -> ")
            }) {
                dotType = .head
            } else if commit.parents.count > 1 {
                dotType = .merge
            } else {
                dotType = .default
            }

            dots.append(
                GraphDot(
                    center: position,
                    lane: dotLane,
                    type: dotType,
                    colorIndex: dotColor,
                    isHighlighted: isHighlighted
                )
            )

            var pathByNext: [String: PathHelper] = [:]
            for path in unsolved where pathByNext[path.next] == nil {
                pathByNext[path.next] = path
            }

            for parentHash in commit.parents.dropFirst() {
                if let parent = pathByNext[parentHash] {
                    if isHighlighted && !parent.isHighlighted {
                        parent.go(
                            toX: parent.lastX,
                            y: offsetY + halfHeight,
                            halfHeight: halfHeight
                        )
                        let highlightedPath = parent.highlight()
                        mutablePaths.append(highlightedPath)
                    }

                    links.append(
                        GraphLink(
                            start: position,
                            control: CGPoint(x: parent.lastX, y: position.y),
                            end: CGPoint(x: parent.lastX, y: offsetY + halfHeight),
                            colorIndex: parent.colorIndex,
                            isHighlighted: isHighlighted
                        )
                    )
                } else {
                    offsetX += unitWidth
                    let target = CGPoint(x: offsetX, y: position.y + halfHeight)
                    let path = PathHelper(
                        next: parentHash,
                        isHighlighted: isHighlighted,
                        colorIndex: colorPicker.next(),
                        start: target
                    )
                    unsolved.append(path)
                    mutablePaths.append(path.path)
                    pathByNext[parentHash] = path
                    maxLane = max(maxLane, lane(forX: target.x))

                    links.append(
                        GraphLink(
                            start: position,
                            control: CGPoint(x: target.x, y: position.y),
                            end: target,
                            colorIndex: path.colorIndex,
                            isHighlighted: isHighlighted
                        )
                    )
                }
            }

            metadata[commit.hash] = GraphCommitMetadata(
                colorIndex: dotColor,
                isHighlighted: isHighlighted,
                leftMargin: max(offsetX, maxOffsetOld) + halfWidth + 2
            )
        }

        let endY = (Double(commits.count) - halfHeight) * unitHeight
        for (index, path) in unsolved.enumerated() {
            if path.pointCount == 1,
               let firstPoint = path.firstPoint,
               abs(firstPoint.y - endY) < 0.0001 {
                continue
            }

            let endX = (Double(index) + halfHeight) * unitWidth + 4
            path.end(atX: endX, y: endY + halfHeight, halfHeight: halfHeight)
            maxLane = max(maxLane, lane(forX: endX))
        }

        let paths = mutablePaths.map {
            GraphPath(
                points: $0.points,
                colorIndex: $0.colorIndex,
                isHighlighted: $0.isHighlighted
            )
        }

        return CommitGraphModel(
            paths: paths,
            links: links,
            dots: dots,
            laneCount: max(1, maxLane + 1),
            commitMetadata: metadata,
            rowIndexByHash: rowByHash
        )
    }

    private static func reachableCommits(
        from headHash: String?,
        commits: [Commit],
        rowByHash: [String: Int]
    ) -> Set<String> {
        guard let headHash, rowByHash[headHash] != nil else { return [] }

        var reachable: Set<String> = []
        var pending = [headHash]

        while let hash = pending.popLast() {
            guard reachable.insert(hash).inserted,
                  let row = rowByHash[hash] else {
                continue
            }
            pending.append(contentsOf: commits[row].parents)
        }

        return reachable
    }

    private static func lane(forX x: Double) -> Int {
        max(0, Int(((x - firstLaneX) / unitWidth).rounded()))
    }
}

nonisolated private final class MutableGraphPath {
    var points: [CGPoint]
    let colorIndex: Int
    let isHighlighted: Bool

    init(points: [CGPoint], colorIndex: Int, isHighlighted: Bool) {
        self.points = points
        self.colorIndex = colorIndex
        self.isHighlighted = isHighlighted
    }
}

nonisolated private final class PathHelper {
    private(set) var path: MutableGraphPath
    var next: String
    private(set) var lastX: Double
    private var lastY: Double
    private var endY = 0.0

    var colorIndex: Int { path.colorIndex }
    var isHighlighted: Bool { path.isHighlighted }
    var pointCount: Int { path.points.count }
    var firstPoint: CGPoint? { path.points.first }

    init(
        next: String,
        isHighlighted: Bool,
        colorIndex: Int,
        start: CGPoint
    ) {
        self.next = next
        self.lastX = start.x
        self.lastY = start.y
        self.path = MutableGraphPath(
            points: [start],
            colorIndex: colorIndex,
            isHighlighted: isHighlighted
        )
    }

    func pass(x: Double, y: Double, halfHeight: Double) {
        if x > lastX {
            add(x: lastX, y: lastY)
            add(x: x, y: y - halfHeight)
        } else if x < lastX {
            add(x: lastX, y: y - halfHeight)
            let adjustedY = y + halfHeight
            add(x: x, y: adjustedY)
        }
        lastX = x
        lastY = y
    }

    func go(toX x: Double, y: Double, halfHeight: Double) {
        if x > lastX {
            add(x: lastX, y: lastY)
            add(x: x, y: y - halfHeight)
        } else if x < lastX {
            var minimumY = y - halfHeight
            if minimumY > lastY {
                minimumY -= halfHeight
            }
            add(x: lastX, y: minimumY)
            add(x: x, y: y)
        }
        lastX = x
        lastY = y
    }

    func end(atX x: Double, y: Double, halfHeight: Double) {
        if x > lastX {
            add(x: lastX, y: lastY)
            add(x: x, y: y - halfHeight)
        } else if x < lastX {
            add(x: lastX, y: y - halfHeight)
        }
        add(x: x, y: y)
        lastX = x
        lastY = y
    }

    @discardableResult
    func highlight() -> MutableGraphPath {
        let colorIndex = path.colorIndex
        add(x: lastX, y: lastY)
        path = MutableGraphPath(
            points: [CGPoint(x: lastX, y: lastY)],
            colorIndex: colorIndex,
            isHighlighted: true
        )
        endY = 0
        return path
    }

    private func add(x: Double, y: Double) {
        guard endY < y else { return }
        path.points.append(CGPoint(x: x, y: y))
        endY = y
    }
}

nonisolated private struct ColorPicker {
    private let colorCount: Int
    private var queue: [Int] = []

    init(colorCount: Int) {
        self.colorCount = max(1, colorCount)
    }

    mutating func next() -> Int {
        if queue.isEmpty {
            queue = Array(0..<colorCount)
        }
        return queue.removeFirst()
    }

    mutating func recycle(_ index: Int) {
        guard !queue.contains(index) else { return }
        queue.append(index)
    }
}
