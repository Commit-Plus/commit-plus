//
//  ConflictResolutionModels.swift
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

enum ConflictSectionResolution: String, CaseIterable, Sendable {
    case current
    case incoming
    case both
    case bothIncomingFirst
    case manual
}

enum ConflictSectionKind: Equatable, Sendable {
    case context
    case conflict
}

struct ConflictResolutionSection: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: ConflictSectionKind
    var contextText: String
    var currentText: String
    var incomingText: String
    var resolution: ConflictSectionResolution
    var manualResult: String

    var isConflict: Bool {
        kind == .conflict
    }

    var isResolved: Bool {
        guard isConflict else { return true }
        return resolution != .manual || !manualResult.isEmpty
    }

    var preferredResultText: String {
        switch resolution {
        case .current:
            return currentText
        case .incoming:
            return incomingText
        case .both:
            return currentText + incomingText
        case .bothIncomingFirst:
            return incomingText + currentText
        case .manual:
            return manualResult
        }
    }

    var editorText: String {
        guard isConflict else { return contextText }
        if !manualResult.isEmpty {
            return manualResult
        }
        return preferredResultText
    }

    var resolvedText: String {
        isConflict ? editorText : contextText
    }

    var currentPaneText: String {
        isConflict ? currentText : contextText
    }

    var incomingPaneText: String {
        isConflict ? incomingText : contextText
    }

    var isCurrentSelected: Bool {
        resolution == .current || resolution == .both || resolution == .bothIncomingFirst
    }

    var isIncomingSelected: Bool {
        resolution == .incoming || resolution == .both || resolution == .bothIncomingFirst
    }

    mutating func setCurrentSelected(_ isSelected: Bool) {
        updateResolution(currentSelected: isSelected, incomingSelected: isIncomingSelected)
    }

    mutating func setIncomingSelected(_ isSelected: Bool) {
        updateResolution(currentSelected: isCurrentSelected, incomingSelected: isSelected)
    }

    private mutating func updateResolution(currentSelected: Bool, incomingSelected: Bool) {
        manualResult = ""

        switch (currentSelected, incomingSelected) {
        case (true, true):
            resolution = .both
        case (true, false):
            resolution = .current
        case (false, true):
            resolution = .incoming
        case (false, false):
            resolution = .manual
        }
    }

    static func context(_ text: String) -> ConflictResolutionSection {
        ConflictResolutionSection(
            kind: .context,
            contextText: text,
            currentText: "",
            incomingText: "",
            resolution: .manual,
            manualResult: ""
        )
    }

    static func conflict(current: String, incoming: String) -> ConflictResolutionSection {
        ConflictResolutionSection(
            kind: .conflict,
            contextText: "",
            currentText: current,
            incomingText: incoming,
            resolution: .manual,
            manualResult: ""
        )
    }
}

struct ConflictResolutionDocument: Equatable, Sendable {
    var sections: [ConflictResolutionSection]
    var currentContent: String
    var incomingContent: String
    var manualResolvedText: String? = nil

    var conflictCount: Int {
        sections.filter(\.isConflict).count
    }

    var resolvedText: String {
        manualResolvedText ?? sections.map(\.resolvedText).joined()
    }

    func allConflictsUse(_ resolution: ConflictSectionResolution) -> Bool {
        let conflictSections = sections.filter(\.isConflict)
        guard !conflictSections.isEmpty else { return false }
        return conflictSections.allSatisfy { $0.resolution == resolution }
    }

    func allConflictsSelect(_ resolution: ConflictSectionResolution) -> Bool {
        let conflictSections = sections.filter(\.isConflict)
        guard !conflictSections.isEmpty else { return false }

        switch resolution {
        case .current:
            return conflictSections.allSatisfy(\.isCurrentSelected)
        case .incoming:
            return conflictSections.allSatisfy(\.isIncomingSelected)
        case .both, .bothIncomingFirst, .manual:
            return conflictSections.allSatisfy { $0.resolution == resolution }
        }
    }

    mutating func selectAllConflicts(_ resolution: ConflictSectionResolution) {
        manualResolvedText = nil
        for index in sections.indices where sections[index].isConflict {
            sections[index].manualResult = ""
            sections[index].resolution = resolution
        }
    }

    mutating func setAllConflictsSelected(
        _ isSelected: Bool,
        for resolution: ConflictSectionResolution
    ) {
        manualResolvedText = nil
        for index in sections.indices where sections[index].isConflict {
            switch resolution {
            case .current:
                sections[index].setCurrentSelected(isSelected)
            case .incoming:
                sections[index].setIncomingSelected(isSelected)
            case .both, .bothIncomingFirst, .manual:
                sections[index].manualResult = ""
                sections[index].resolution = isSelected ? resolution : .manual
            }
        }
    }

    static func parse(
        _ text: String,
        currentContent: String? = nil,
        incomingContent: String? = nil
    ) throws -> ConflictResolutionDocument {
        enum ParseState {
            case context
            case current
            case incoming
        }

        let lines = splitPreservingNewlines(in: text)
        var sections: [ConflictResolutionSection] = []
        var contextBuffer = ""
        var currentBuffer = ""
        var incomingBuffer = ""
        var state: ParseState = .context

        func flushContext() {
            guard !contextBuffer.isEmpty else { return }
            sections.append(.context(contextBuffer))
            contextBuffer = ""
        }

        func flushConflict() {
            sections.append(.conflict(current: currentBuffer, incoming: incomingBuffer))
            currentBuffer = ""
            incomingBuffer = ""
        }

        for line in lines {
            switch state {
            case .context:
                if line.hasPrefix("<<<<<<<") {
                    flushContext()
                    state = .current
                } else {
                    contextBuffer += line
                }
            case .current:
                if line.hasPrefix("=======") {
                    state = .incoming
                } else {
                    currentBuffer += line
                }
            case .incoming:
                if line.hasPrefix(">>>>>>>") {
                    flushConflict()
                    state = .context
                } else {
                    incomingBuffer += line
                }
            }
        }

        guard state == .context else {
            throw GitError.commandFailed("Could not parse conflict markers in file.")
        }

        flushContext()

        let resolvedCurrent = currentContent ?? sections.map(\.currentPaneText).joined()
        let resolvedIncoming = incomingContent ?? sections.map(\.incomingPaneText).joined()

        return ConflictResolutionDocument(
            sections: sections,
            currentContent: resolvedCurrent,
            incomingContent: resolvedIncoming,
            manualResolvedText: nil
        )
    }

    private static func splitPreservingNewlines(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var fragments: [String] = []
        var lineStart = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "\n" || text[index] == "\r\n" {
                let nextIndex = text.index(after: index)
                fragments.append(String(text[lineStart..<nextIndex]))
                lineStart = nextIndex
                index = nextIndex
            } else {
                text.formIndex(after: &index)
            }
        }

        if lineStart < text.endIndex {
            fragments.append(String(text[lineStart..<text.endIndex]))
        }

        return fragments
    }
}
