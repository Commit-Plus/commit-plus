//
//  GitDiffModels.swift
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

nonisolated enum DiffLineRendering {
    static let longLineByteThreshold = 4_096
}

nonisolated enum DiffLineType: Hashable, Sendable {
    case context
    case added
    case removed
    case header
    case conflictMarker
}

nonisolated struct DiffLine: Identifiable, Sendable {
    var id: UUID
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
    let type: DiffLineType

    init(id: UUID = UUID(), oldLineNumber: Int?, newLineNumber: Int?, text: String, type: DiffLineType) {
        self.id = id
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
        self.type = type
    }

    var textFingerprint: DiffTextFingerprint { DiffTextFingerprint(text) }
}

nonisolated enum DiffLineBackgroundKind: Equatable, Sendable {
    case added
    case removed
    case conflict
    case plain

    init(_ type: DiffLineType) {
        switch type {
        case .added: self = .added
        case .removed: self = .removed
        case .conflictMarker: self = .conflict
        case .context, .header: self = .plain
        }
    }
}

nonisolated struct DiffLineBackgroundRun: Identifiable, Sendable {
    let id: Int
    let count: Int
    let kind: DiffLineBackgroundKind
}

nonisolated struct DiffHunk: Identifiable, Sendable {
    let id: UUID
    let header: String
    let lines: [DiffLine]
    let backgroundRuns: [DiffLineBackgroundRun]
    let widestLineCandidate: String
    let addedCount: Int
    let removedCount: Int
    let contentRevision: DiffContentRevision

    init(id: UUID = UUID(), header: String, lines: [DiffLine]) {
        self.id = id
        self.header = header
        self.lines = lines

        var runs: [DiffLineBackgroundRun] = []
        var widestLineCandidate = ""
        var widestLineUTF16Count = 0
        var addedCount = 0
        var removedCount = 0
        for (index, line) in lines.enumerated() {
            let kind = DiffLineBackgroundKind(line.type)
            if let last = runs.last, last.kind == kind {
                runs[runs.count - 1] = DiffLineBackgroundRun(
                    id: last.id,
                    count: last.count + 1,
                    kind: kind
                )
            } else {
                runs.append(DiffLineBackgroundRun(id: index, count: 1, kind: kind))
            }
            if line.type == .added { addedCount += 1 }
            if line.type == .removed { removedCount += 1 }
            let utf16Count = line.text.utf16.count
            if utf16Count > widestLineUTF16Count {
                widestLineCandidate = line.text
                widestLineUTF16Count = utf16Count
            }
        }
        backgroundRuns = runs
        self.widestLineCandidate = widestLineCandidate
        self.addedCount = addedCount
        self.removedCount = removedCount
        contentRevision = DiffContentRevision(
            header: header,
            lines: lines.map {
                DiffContentRevision.Line(oldLineNumber: $0.oldLineNumber,
                                         newLineNumber: $0.newLineNumber,
                                         text: $0.text, type: $0.type)
            }
        )
    }

    func replacingLines(_ lines: [DiffLine]) -> Self {
        Self(id: id, header: header, lines: lines)
    }
}

nonisolated enum DiffParser {
    static func parse(_ raw: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentLines: [DiffLine] = []
        var currentHeader = ""
        var oldLine = 0
        var newLine = 0
        var currentHunkID = UUID()
        var occurrences: [String: Int] = [:]

        let lines = raw.components(separatedBy: "\n")
        var inHunk = false

        for line in lines {
            let text = String(line)

            if text.hasPrefix("@@") {
                // Start of hunk
                if inHunk {
                    hunks.append(DiffHunk(id: currentHunkID, header: currentHeader, lines: currentLines))
                }
                inHunk = true
                currentHeader = text
                currentLines = []

                // Parse line numbers: @@ -start,count +start,count @@
                if let range = text.range(of: "@@ -"),
                   let atRange = text[range.upperBound...].range(of: " @@") {
                    let numbersPart = String(text[range.upperBound..<atRange.lowerBound])
                    let parts = numbersPart.split(separator: " ")
                    if parts.count == 2 {
                        let oldPart = parts[0].split(separator: ",")
                        let newPart = parts[1].split(separator: ",")
                        oldLine = Int(oldPart[0]) ?? 0
                        if oldPart.count > 1, let count = Int(oldPart[1]), count == 0 {
                            // Deleted file or new file
                        }
                        newLine = Int(String(newPart[0]).dropFirst()) ?? 0
                        let key = "\(oldLine):\(newLine)"
                        let occurrence = occurrences[key, default: 0]
                        occurrences[key] = occurrence + 1
                        currentHunkID = DiffHunkIdentity.make(
                            oldStart: oldLine, newStart: newLine, occurrence: occurrence)
                    }
                }
                continue
            }

            if !inHunk {
                continue
            }

            guard !text.isEmpty else {
                currentLines.append(DiffLine(oldLineNumber: nil, newLineNumber: nil, text: "", type: .context))
                continue
            }

            let prefix = text.prefix(1)
            let content = String(text.dropFirst())
            let isConflictMarker = content.hasPrefix("<<<<<<<") || content.hasPrefix("=======") || content.hasPrefix(">>>>>>>")

            switch prefix {
            case "+":
                if isConflictMarker {
                    currentLines.append(DiffLine(oldLineNumber: nil, newLineNumber: newLine, text: content, type: .conflictMarker))
                } else {
                    currentLines.append(DiffLine(oldLineNumber: nil, newLineNumber: newLine, text: content, type: .added))
                }
                newLine += 1
            case "-":
                if isConflictMarker {
                    currentLines.append(DiffLine(oldLineNumber: oldLine, newLineNumber: nil, text: content, type: .conflictMarker))
                } else {
                    currentLines.append(DiffLine(oldLineNumber: oldLine, newLineNumber: nil, text: content, type: .removed))
                }
                oldLine += 1
            case " ":
                if isConflictMarker {
                    currentLines.append(DiffLine(oldLineNumber: oldLine, newLineNumber: newLine, text: content, type: .conflictMarker))
                } else {
                    currentLines.append(DiffLine(oldLineNumber: oldLine, newLineNumber: newLine, text: content, type: .context))
                }
                oldLine += 1
                newLine += 1
            case "\\":
                // "\ No newline at end of file"
                currentLines.append(DiffLine(oldLineNumber: nil, newLineNumber: nil, text: text, type: .header))
            default:
                break
            }
        }

        if inHunk && !currentLines.isEmpty {
            hunks.append(DiffHunk(id: currentHunkID, header: currentHeader, lines: currentLines))
        }

        return hunks
    }
}
