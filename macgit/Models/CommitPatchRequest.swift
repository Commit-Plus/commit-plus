//
//  CommitPatchRequest.swift
//  macgit
//
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software; you can redistribute it and/or modify
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

nonisolated struct CommitPatchRequest: Sendable {
    enum Direction: String, Sendable {
        case apply = "Apply"
        case revert = "Revert"
    }

    // Line numbers are relative to the immutable source commit, never the working copy.
    struct Line: Hashable, Sendable {
        let old: Int?
        let new: Int?

        init(_ line: DiffLine) {
            old = line.oldLineNumber
            new = line.newLineNumber
        }

        init(old: Int?, new: Int?) {
            self.old = old
            self.new = new
        }
    }

    let commit: String
    let files: [CommitFileChange]
    let direction: Direction
    // nil means complete files; a nonempty set means only these changed lines in one file.
    let lines: Set<Line>?
    let scope: String
}
