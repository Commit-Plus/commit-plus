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

nonisolated enum ConflictResultLineHighlights {
    static func changedLineIndices(result: String, baseline: String) -> Set<Int> {
        guard !Task.isCancelled, result != baseline else { return [] }
        let resultLines = lines(in: result)
        let baselineLines = lines(in: baseline)
        guard !Task.isCancelled else { return [] }
        let difference = resultLines.difference(from: baselineLines)

        return Set(difference.compactMap { change in
            guard case .insert(let offset, _, _) = change else { return nil }
            return offset
        })
    }

    static func blankLineIndices(in text: String) -> Set<Int> {
        guard !Task.isCancelled else { return [] }
        let textLines = lines(in: text)
        return Set(textLines.indices.filter { index in
            textLines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }

    private static func lines(in text: String) -> [String] {
        text.components(separatedBy: "\n")
    }
}
