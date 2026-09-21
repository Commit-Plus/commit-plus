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

struct ConflictPanelAlignment {
    let incomingRows: [ConflictCodeLine]
    let currentRows: [ConflictCodeLine]
    let resultRows: [ConflictCodeLine]
    let incomingColumnCount: Int
    let currentColumnCount: Int
    private let conflictRowIndices: [Int: Int]

    init(document: ConflictResolutionDocument) {
        var incomingBuilder = PaneLineBuilder()
        var currentBuilder = PaneLineBuilder()
        var resultBuilder = PaneLineBuilder()

        var incomingRows: [ConflictCodeLine] = []
        var currentRows: [ConflictCodeLine] = []
        var resultRows: [ConflictCodeLine] = []

        for (sectionIndex, section) in document.sections.enumerated() {
            let incomingLines = Self.lines(of: section.incomingPaneText)
            let currentLines = Self.lines(of: section.currentPaneText)
            let resultLines = Self.lines(of: section.resolvedText)
            let alignedLineCount = max(incomingLines.count, currentLines.count, resultLines.count)
            let conflictSectionIndex = section.isConflict ? sectionIndex : nil

            incomingRows += incomingBuilder.rows(
                from: incomingLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict,
                conflictSectionIndex: conflictSectionIndex
            )
            currentRows += currentBuilder.rows(
                from: currentLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict,
                conflictSectionIndex: conflictSectionIndex
            )
            resultRows += resultBuilder.rows(
                from: resultLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict,
                conflictSectionIndex: conflictSectionIndex
            )
        }

        self.incomingRows = incomingRows
        self.currentRows = currentRows
        self.resultRows = resultRows
        self.incomingColumnCount = Self.maximumColumns(in: incomingRows)
        self.currentColumnCount = Self.maximumColumns(in: currentRows)
        self.conflictRowIndices = Dictionary(uniqueKeysWithValues: incomingRows.enumerated().compactMap { index, row in
            guard row.startsConflict, let section = row.conflictSectionIndex else { return nil }
            return (section, index)
        })
    }

    func rowIndex(forConflictSectionIndex sectionIndex: Int) -> Int? {
        conflictRowIndices[sectionIndex]
    }

    private static func maximumColumns(in rows: [ConflictCodeLine]) -> Int {
        rows.reduce(0) { maximum, row in
            max(maximum, row.text.utf16.reduce(0) { $0 + ($1 == 9 ? 8 : 1) })
        }
    }

    private static func lines(of text: String) -> [String] {
        var components = text.components(separatedBy: "\n")
        if components.last == "" {
            components.removeLast()
        }
        return components
    }
}

private struct PaneLineBuilder {
    private var nextLineNumber = 1

    mutating func rows(
        from lines: [String],
        alignedLineCount: Int,
        isConflict: Bool,
        conflictSectionIndex: Int?
    ) -> [ConflictCodeLine] {
        guard alignedLineCount > 0 else { return [] }

        return (0..<alignedLineCount).map { index in
            let startsConflict = index == 0 && isConflict

            guard index < lines.count else {
                return .placeholder(
                    isConflict: isConflict,
                    conflictSectionIndex: conflictSectionIndex,
                    startsConflict: startsConflict
                )
            }

            defer { nextLineNumber += 1 }
            return .actual(
                lineNumber: nextLineNumber,
                text: lines[index],
                isConflict: isConflict,
                conflictSectionIndex: conflictSectionIndex,
                startsConflict: startsConflict
            )
        }
    }
}
