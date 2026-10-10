// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated enum DiffLineIdentityMatcher {
    private struct Key: Hashable {
        let type: DiffLineType
        let text: String
    }

    static func restoringIDs(from oldHunks: [DiffHunk], in newHunks: [DiffHunk]) -> [DiffHunk] {
        let oldByID = Dictionary(uniqueKeysWithValues: oldHunks.map { ($0.id, $0) })
        return newHunks.map { newHunk in
            guard let oldHunk = oldByID[newHunk.id] else { return newHunk }
            return restoringIDs(from: oldHunk, in: newHunk)
        }
    }

    static func restoringIDs(from oldHunk: DiffHunk, in newHunk: DiffHunk) -> DiffHunk {
        var candidates: [Key: [Int]] = [:]
        for (index, line) in oldHunk.lines.enumerated() {
            candidates[Key(type: line.type, text: line.text), default: []].append(index)
        }
        var used = Set<Int>()
        var lines = newHunk.lines
        for index in lines.indices {
            let key = Key(type: lines[index].type, text: lines[index].text)
            let available = candidates[key, default: []].filter { !used.contains($0) }
            guard let match = bestMatch(for: index, candidates: available,
                                        oldLines: oldHunk.lines, newLines: lines) else { continue }
            lines[index].id = oldHunk.lines[match].id
            used.insert(match)
        }
        return newHunk.replacingLines(lines)
    }

    private static func bestMatch(for newIndex: Int, candidates: [Int],
                                  oldLines: [DiffLine], newLines: [DiffLine]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }
        let scored = candidates.map { oldIndex in
            (oldIndex, neighbourScore(oldIndex: oldIndex, newIndex: newIndex,
                                      oldLines: oldLines, newLines: newLines))
        }
        guard let maximum = scored.map(\.1).max(), maximum > 0 else { return nil }
        let winners = scored.filter { $0.1 == maximum }
        return winners.count == 1 ? winners[0].0 : nil
    }

    private static func neighbourScore(oldIndex: Int, newIndex: Int,
                                       oldLines: [DiffLine], newLines: [DiffLine]) -> Int {
        var score = 0
        for delta in [-2, -1, 1, 2] {
            let old = oldIndex + delta
            let new = newIndex + delta
            guard oldLines.indices.contains(old), newLines.indices.contains(new) else { continue }
            if oldLines[old].type == newLines[new].type && oldLines[old].text == newLines[new].text {
                score += abs(delta) == 1 ? 2 : 1
            }
        }
        return score
    }
}
