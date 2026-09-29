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

nonisolated struct CommitGraphGenerationResult: @unchecked Sendable {
    let model: CommitGraphModel
    let state: CommitGraphGenerationState
}

nonisolated struct CommitGraphGenerationState: @unchecked Sendable {
    fileprivate var mutablePaths: [MutableGraphPath]
    fileprivate var links: [GraphLink]
    fileprivate var dots: [GraphDot]
    fileprivate var metadata: [String: GraphCommitMetadata]
    fileprivate var unsolved: [PathHelper]
    fileprivate var offsetY: Double
    fileprivate var colorPicker: ColorPicker
    fileprivate var maxLane: Int
    fileprivate var rowByHash: [String: Int]
    fileprivate var rowSlices: [CommitGraphRowSlice]
    fileprivate var commitHashes: [String]
    fileprivate let highlighting: CommitGraphHighlighting
    fileprivate let headHash: String?
    fileprivate let highlightRootHash: String?

    fileprivate func copied() -> CommitGraphGenerationState {
        let copiedPaths = mutablePaths.map { $0.copied() }
        let copiedPathByID = Dictionary(
            uniqueKeysWithValues: zip(mutablePaths, copiedPaths).map {
                (ObjectIdentifier($0.0), $0.1)
            }
        )
        let copiedUnsolved = unsolved.compactMap { helper -> PathHelper? in
            guard let copiedPath = copiedPathByID[ObjectIdentifier(helper.path)] else {
                return nil
            }
            return helper.copied(path: copiedPath)
        }

        return CommitGraphGenerationState(
            mutablePaths: copiedPaths,
            links: links,
            dots: dots,
            metadata: metadata,
            unsolved: copiedUnsolved,
            offsetY: offsetY,
            colorPicker: colorPicker,
            maxLane: maxLane,
            rowByHash: rowByHash,
            rowSlices: rowSlices,
            commitHashes: commitHashes,
            highlighting: highlighting,
            headHash: headHash,
            highlightRootHash: highlightRootHash
        )
    }
}

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
        generateIncremental(
            commits: commits,
            highlighting: highlighting,
            headHash: headHash,
            highlightRootHash: highlightRootHash
        ).model
    }

    @concurrent
    static func generateIncrementalAsync(
        commits: [Commit],
        highlighting: CommitGraphHighlighting,
        headHash: String?,
        highlightRootHash: String?
    ) async -> CommitGraphGenerationResult {
        generateIncremental(
            commits: commits,
            highlighting: highlighting,
            headHash: headHash,
            highlightRootHash: highlightRootHash
        )
    }

    @concurrent
    static func appendAsync(
        commits: [Commit],
        to previousState: CommitGraphGenerationState,
        allCommits: [Commit],
        highlighting: CommitGraphHighlighting,
        headHash: String?,
        highlightRootHash: String?
    ) async -> CommitGraphGenerationResult? {
        append(
            commits: commits,
            to: previousState,
            allCommits: allCommits,
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
        generateIncremental(
            commits: commits,
            highlighting: highlighting,
            headHash: headHash,
            highlightRootHash: highlightRootHash
        ).model
    }

    static func generateIncremental(
        commits: [Commit],
        highlighting: CommitGraphHighlighting,
        headHash: String?,
        highlightRootHash: String?
    ) -> CommitGraphGenerationResult {
        let rowByHash = Dictionary(
            uniqueKeysWithValues: commits.enumerated().map { ($0.element.hash, $0.offset) }
        )
        let highlightedCommits = reachableCommits(
            from: highlightRootHash,
            commits: commits,
            rowByHash: rowByHash
        )

        var state = CommitGraphGenerationState(
            mutablePaths: [],
            links: [],
            dots: [],
            metadata: [:],
            unsolved: [],
            offsetY: -halfHeight,
            colorPicker: ColorPicker(colorCount: colorCount),
            maxLane: 0,
            rowByHash: rowByHash,
            rowSlices: [],
            commitHashes: commits.map(\.hash),
            highlighting: highlighting,
            headHash: headHash,
            highlightRootHash: highlightRootHash
        )

        process(commits: commits, highlightedCommits: highlightedCommits, state: &state)
        let model = snapshot(state: &state, appendedRowStart: 0)
        return CommitGraphGenerationResult(model: model, state: state)
    }

    static func append(
        commits: [Commit],
        to previousState: CommitGraphGenerationState,
        allCommits: [Commit],
        highlighting: CommitGraphHighlighting,
        headHash: String?,
        highlightRootHash: String?
    ) -> CommitGraphGenerationResult? {
        let previousCount = previousState.commitHashes.count
        guard !commits.isEmpty,
              previousState.highlighting == highlighting,
              previousState.headHash == headHash,
              previousState.highlightRootHash == highlightRootHash,
              allCommits.count == previousCount + commits.count,
              Array(allCommits.prefix(previousCount).map(\.hash)) == previousState.commitHashes,
              Array(allCommits.suffix(commits.count).map(\.hash)) == commits.map(\.hash) else {
            return nil
        }

        var state = previousState.copied()
        state.rowByHash = Dictionary(
            uniqueKeysWithValues: allCommits.enumerated().map { ($0.element.hash, $0.offset) }
        )
        state.commitHashes = allCommits.map(\.hash)
        let highlightedCommits = reachableCommits(
            from: highlightRootHash,
            commits: allCommits,
            rowByHash: state.rowByHash
        )
        process(commits: commits, highlightedCommits: highlightedCommits, state: &state)
        let model = snapshot(state: &state, appendedRowStart: previousCount)
        return CommitGraphGenerationResult(model: model, state: state)
    }

    private static func process(
        commits: [Commit],
        highlightedCommits: Set<String>,
        state: inout CommitGraphGenerationState
    ) {
        var ended: [PathHelper] = []

        for commit in commits {
            var major: PathHelper?
            state.offsetY += unitHeight

            var offsetX = 4 - halfWidth
            let maxOffsetOld = state.unsolved.last?.lastX ?? offsetX + unitWidth
            var isHighlighted = false

            for path in state.unsolved {
                if path.next == commit.hash {
                    if major == nil {
                        offsetX += unitWidth
                        major = path
                        isHighlighted = path.isHighlighted

                        if let firstParent = commit.parents.first {
                            path.next = firstParent
                            path.go(toX: offsetX, y: state.offsetY, halfHeight: halfHeight)
                        } else {
                            path.end(atX: offsetX, y: state.offsetY, halfHeight: halfHeight)
                            ended.append(path)
                        }
                    } else if let major {
                        path.end(atX: major.lastX, y: state.offsetY, halfHeight: halfHeight)
                        ended.append(path)
                        isHighlighted = isHighlighted || path.isHighlighted
                    }
                } else {
                    offsetX += unitWidth
                    path.pass(x: offsetX, y: state.offsetY, halfHeight: halfHeight)
                }
            }

            if !ended.isEmpty {
                let endedIDs = Set(ended.map(ObjectIdentifier.init))
                for path in ended {
                    state.colorPicker.recycle(path.colorIndex)
                }
                state.unsolved.removeAll { endedIDs.contains(ObjectIdentifier($0)) }
                ended.removeAll(keepingCapacity: true)
            }

            if !isHighlighted {
                switch state.highlighting {
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
                        colorIndex: state.colorPicker.next(),
                        start: CGPoint(x: offsetX, y: state.offsetY)
                    )
                    state.unsolved.append(path)
                    state.mutablePaths.append(path.path)
                    major = path
                }
            } else if let major,
                      isHighlighted,
                      !major.isHighlighted,
                      !commit.parents.isEmpty {
                let highlightedPath = major.highlight()
                state.mutablePaths.append(highlightedPath)
            }

            let position = CGPoint(x: major?.lastX ?? offsetX, y: state.offsetY)
            let dotColor = major?.colorIndex ?? 0
            let dotLane = lane(forX: position.x)
            state.maxLane = max(state.maxLane, dotLane)

            let dotType: GraphDotType
            if commit.hash == state.headHash || commit.refs.contains(where: {
                $0 == "HEAD" || $0.hasPrefix("HEAD -> ")
            }) {
                dotType = .head
            } else if commit.parents.count > 1 {
                dotType = .merge
            } else {
                dotType = .default
            }

            state.dots.append(
                GraphDot(
                    center: position,
                    lane: dotLane,
                    type: dotType,
                    colorIndex: dotColor,
                    isHighlighted: isHighlighted
                )
            )

            var pathByNext: [String: PathHelper] = [:]
            for path in state.unsolved where pathByNext[path.next] == nil {
                pathByNext[path.next] = path
            }

            for parentHash in commit.parents.dropFirst() {
                if let parent = pathByNext[parentHash] {
                    if isHighlighted && !parent.isHighlighted {
                        parent.go(
                            toX: parent.lastX,
                            y: state.offsetY + halfHeight,
                            halfHeight: halfHeight
                        )
                        let highlightedPath = parent.highlight()
                        state.mutablePaths.append(highlightedPath)
                    }

                    state.links.append(
                        GraphLink(
                            start: position,
                            control: CGPoint(x: parent.lastX, y: position.y),
                            end: CGPoint(x: parent.lastX, y: state.offsetY + halfHeight),
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
                        colorIndex: state.colorPicker.next(),
                        start: target
                    )
                    state.unsolved.append(path)
                    state.mutablePaths.append(path.path)
                    pathByNext[parentHash] = path
                    state.maxLane = max(state.maxLane, lane(forX: target.x))

                    state.links.append(
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

            state.metadata[commit.hash] = GraphCommitMetadata(
                colorIndex: dotColor,
                isHighlighted: isHighlighted,
                leftMargin: max(offsetX, maxOffsetOld) + halfWidth + 2
            )
        }
    }

    private static func snapshot(
        state: inout CommitGraphGenerationState,
        appendedRowStart: Int
    ) -> CommitGraphModel {
        let snapshotPaths = state.mutablePaths.map { $0.copied() }
        let snapshotPathByID = Dictionary(
            uniqueKeysWithValues: zip(state.mutablePaths, snapshotPaths).map {
                (ObjectIdentifier($0.0), $0.1)
            }
        )
        let endY = (Double(state.dots.count) - halfHeight) * unitHeight
        var snapshotMaxLane = state.maxLane
        for (index, path) in state.unsolved.enumerated() {
            if path.pointCount == 1,
               let firstPoint = path.firstPoint,
               abs(firstPoint.y - endY) < 0.0001 {
                continue
            }

            let endX = (Double(index) + halfHeight) * unitWidth + 4
            if let snapshotPath = snapshotPathByID[ObjectIdentifier(path.path)] {
                path.copied(path: snapshotPath).end(
                    atX: endX,
                    y: endY + halfHeight,
                    halfHeight: halfHeight
                )
            }
            snapshotMaxLane = max(snapshotMaxLane, lane(forX: endX))
        }

        let paths = snapshotPaths.map {
            GraphPath(
                points: $0.points,
                colorIndex: $0.colorIndex,
                isHighlighted: $0.isHighlighted
            )
        }

        let newRowSlices = CommitGraphRowSlice.makeRows(
            paths: paths,
            links: state.links,
            dots: state.dots,
            rowRange: appendedRowStart..<state.dots.count,
            rowCount: state.dots.count
        )
        state.rowSlices.append(contentsOf: newRowSlices)

        return CommitGraphModel(
            paths: paths,
            links: state.links,
            dots: state.dots,
            laneCount: max(1, snapshotMaxLane + 1),
            commitMetadata: state.metadata,
            rowIndexByHash: state.rowByHash,
            rowSlices: state.rowSlices
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

nonisolated fileprivate final class MutableGraphPath {
    var points: [CGPoint]
    let colorIndex: Int
    let isHighlighted: Bool

    init(points: [CGPoint], colorIndex: Int, isHighlighted: Bool) {
        self.points = points
        self.colorIndex = colorIndex
        self.isHighlighted = isHighlighted
    }

    func copied() -> MutableGraphPath {
        MutableGraphPath(
            points: points,
            colorIndex: colorIndex,
            isHighlighted: isHighlighted
        )
    }
}

nonisolated fileprivate final class PathHelper {
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

    private init(
        next: String,
        lastX: Double,
        lastY: Double,
        endY: Double,
        path: MutableGraphPath
    ) {
        self.next = next
        self.lastX = lastX
        self.lastY = lastY
        self.endY = endY
        self.path = path
    }

    func copied(path: MutableGraphPath) -> PathHelper {
        PathHelper(
            next: next,
            lastX: lastX,
            lastY: lastY,
            endY: endY,
            path: path
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

nonisolated fileprivate struct ColorPicker {
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
