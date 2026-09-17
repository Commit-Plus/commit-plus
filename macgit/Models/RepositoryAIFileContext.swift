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

nonisolated enum RepositoryAIFileSource: String, Codable, CaseIterable, Sendable {
    case workingTree
    case index
    case commit

    var displayName: String {
        switch self {
        case .workingTree: "Working Tree"
        case .index: "Staged"
        case .commit: "Commit"
        }
    }
}

/// A repository-relative file identity that Commit+ discovered from Git state.
/// It is intentionally not a general filesystem URL.
nonisolated struct RepositoryAIFileReference: Identifiable, Codable, Equatable, Hashable, Sendable {
    let path: String
    let source: RepositoryAIFileSource
    let objectID: String?
    let fingerprint: String

    var id: String { "\(source.rawValue):\(objectID ?? "working"): \(path):\(fingerprint)" }

    var displayLabel: String {
        source == .commit
            ? "\(String((objectID ?? "").prefix(8))) · \(path)"
            : "\(source.displayName) · \(path)"
    }
}

nonisolated struct RepositoryAITextRange: Codable, Equatable, Hashable, Sendable {
    let startLine: Int
    let endLine: Int

    init?(startLine: Int, endLine: Int) {
        guard startLine > 0, endLine >= startLine else { return nil }
        self.startLine = startLine
        self.endLine = endLine
    }

    func isContained(in range: RepositoryAITextRange?) -> Bool {
        guard let range else { return false }
        return startLine >= range.startLine && endLine <= range.endLine
    }

    private enum CodingKeys: String, CodingKey {
        case startLine
        case endLine
        case start
        case end
        case line
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let startLine = try container.decodeIfPresent(Int.self, forKey: .startLine),
           let endLine = try container.decodeIfPresent(Int.self, forKey: .endLine),
           let range = Self(startLine: startLine, endLine: endLine) {
            self = range
            return
        }
        let start = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .start)
        let end = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .end)
        guard let range = Self(
            startLine: try start.decode(Int.self, forKey: .line),
            endLine: try end.decode(Int.self, forKey: .line)
        ) else {
            throw DecodingError.dataCorruptedError(forKey: .start, in: container, debugDescription: "Citation ranges must use positive, ordered line numbers.")
        }
        self = range
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startLine, forKey: .startLine)
        try container.encode(endLine, forKey: .endLine)
    }
}

nonisolated struct RepositoryAIDiffRange: Codable, Equatable, Hashable, Sendable {
    let hunkIndex: Int
    let base: RepositoryAITextRange?
    let head: RepositoryAITextRange?

    init?(hunkIndex: Int, base: RepositoryAITextRange?, head: RepositoryAITextRange?) {
        guard hunkIndex >= 0, base != nil || head != nil else { return nil }
        self.hunkIndex = hunkIndex
        self.base = base
        self.head = head
    }
}

nonisolated struct RepositoryAICitation: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    /// Opaque ID supplied to the provider. It never contains an absolute path.
    let evidenceID: String
    let label: String
    let textRange: RepositoryAITextRange?
    let diffRange: RepositoryAIDiffRange?

    init(
        id: String = UUID().uuidString,
        evidenceID: String,
        label: String,
        textRange: RepositoryAITextRange? = nil,
        diffRange: RepositoryAIDiffRange? = nil
    ) {
        self.id = id
        self.evidenceID = evidenceID
        self.label = label
        self.textRange = textRange
        self.diffRange = diffRange
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case evidenceID
        case label
        case textRange
        case diffRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let evidenceID = try container.decode(String.self, forKey: .evidenceID)
        let label = try container.decode(String.self, forKey: .label)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            evidenceID: evidenceID,
            label: label,
            textRange: try container.decodeIfPresent(RepositoryAITextRange.self, forKey: .textRange),
            diffRange: try container.decodeIfPresent(RepositoryAIDiffRange.self, forKey: .diffRange)
        )
    }
}

nonisolated struct RepositoryAIAnswer: Equatable, Sendable {
    let text: String
    let citations: [RepositoryAICitation]
    let isTruncated: Bool

    init(text: String, citations: [RepositoryAICitation] = [], isTruncated: Bool = false) {
        self.text = text
        self.citations = citations
        self.isTruncated = isTruncated
    }

    /// Keeps Phase 1 provider adapters source-compatible while they migrate to
    /// structured responses.
    init(_ text: String) {
        self.init(text: text, citations: [])
    }
}

nonisolated enum RepositoryAIAnswerDecoder {
    private struct WireAnswer: Decodable {
        let text: String
        let citations: [RepositoryAICitation]?
    }

    /// Cloud adapters use this as a compatibility boundary while providers
    /// roll out native structured output. Only file-evidence requests require
    /// the citation schema; other contexts retain their provider text without
    /// ever manufacturing a citation set.
    static func decodeProviderText(
        _ text: String,
        requiresStructuredResponse: Bool = false
    ) throws -> RepositoryAIAnswer {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryAIError.emptyResponse }
        guard trimmed.hasPrefix("{") else { return RepositoryAIAnswer(trimmed) }
        guard let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WireAnswer.self, from: data),
              !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            guard !requiresStructuredResponse else {
                throw RepositoryAIError.invalidResponse("Repository AI returned malformed structured output.")
            }
            if let recoveredText = recoveredText(fromMalformedJSONObject: trimmed) {
                return RepositoryAIAnswer(recoveredText)
            }
            return RepositoryAIAnswer(trimmed)
        }
        return RepositoryAIAnswer(text: decoded.text, citations: decoded.citations ?? [])
    }

    /// A provider can occasionally emit a JSON-shaped response whose `text`
    /// value contains unescaped quotes. It is not valid JSON, but displaying
    /// the wrapper is worse than safely recovering the only user-facing field.
    /// Citations are deliberately never recovered this way.
    private static func recoveredText(fromMalformedJSONObject text: String) -> String? {
        guard let prefixRange = text.range(of: #"^\s*\{\s*\"text\"\s*:\s*\""#, options: .regularExpression) else {
            return nil
        }
        let body = String(text[prefixRange.upperBound...])
        let content: String
        if let suffixRange = body.range(of: #"\"\s*\}\s*$"#, options: [.regularExpression, .backwards]) {
            content = String(body[..<suffixRange.lowerBound])
        } else if body.hasSuffix("\"") {
            // The provider hit its output cap before closing the JSON wrapper, so
            // the text value still carries its closing quote.
            content = String(body.dropLast())
        } else {
            // A provider can reach its output cap before the JSON wrapper is
            // closed. The text value remains safe to display as prose.
            content = body
        }
        let recovered = content
            .replacing("\\n", with: "\n")
            .replacing("\\\"", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return recovered.isEmpty ? nil : recovered
    }
}

nonisolated struct RepositoryAIEvidence: Codable, Equatable, Sendable {
    let id: String
    let reference: RepositoryAIFileReference
    let textRange: RepositoryAITextRange?
    let diffRanges: [RepositoryAIDiffRange]
    let fingerprint: String
}

nonisolated struct RepositoryAIEvidenceManifest: Codable, Equatable, Sendable {
    let evidence: [RepositoryAIEvidence]

    init(evidence: [RepositoryAIEvidence]) {
        self.evidence = evidence
    }

    func validatedCitations(from citations: [RepositoryAICitation]) -> (accepted: [RepositoryAICitation], rejected: [RepositoryAICitation]) {
        var seen = Set<String>()
        return citations.reduce(into: (accepted: [RepositoryAICitation](), rejected: [RepositoryAICitation]())) { result, citation in
            guard seen.insert(citation.id).inserted,
                  !citation.evidenceID.isEmpty,
                  !citation.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let item = evidence.first(where: { $0.id == citation.evidenceID }),
                  citation.textRange == nil || citation.textRange!.isContained(in: item.textRange),
                  citation.diffRange == nil || item.diffRanges.contains(citation.diffRange!),
                  citation.textRange != nil || citation.diffRange != nil else {
                result.rejected.append(citation)
                return
            }
            result.accepted.append(citation)
        }
    }

    func evidence(for citation: RepositoryAICitation) -> RepositoryAIEvidence? {
        evidence.first { $0.id == citation.evidenceID }
    }
}

nonisolated struct RepositoryAIFileContext: Equatable, Sendable {
    let reference: RepositoryAIFileReference
    let evidence: RepositoryAIEvidence
    let content: String
    let isTruncated: Bool
    let requestedRange: RepositoryAITextRange?

    var manifest: RepositoryAIEvidenceManifest { RepositoryAIEvidenceManifest(evidence: [evidence]) }
}

nonisolated struct RepositoryAIFileDiff: Equatable, Sendable {
    let reference: RepositoryAIFileReference
    let evidence: RepositoryAIEvidence
    let content: String
    let isTruncated: Bool

    var manifest: RepositoryAIEvidenceManifest { RepositoryAIEvidenceManifest(evidence: [evidence]) }
}

nonisolated enum RepositoryAIFileContextError: LocalizedError, Equatable {
    case invalidPath
    case unavailableFile
    case unsafeFile
    case unsupportedContent
    case staleEvidence

    var errorDescription: String? {
        switch self {
        case .invalidPath: "Repository AI can only inspect a safe repository-relative file path."
        case .unavailableFile: "That file is no longer available in the selected repository context."
        case .unsafeFile: "Repository AI cannot inspect that file because it is outside the safe repository context."
        case .unsupportedContent: "Repository AI can only inspect bounded UTF-8 text files."
        case .staleEvidence: "That citation no longer matches the repository evidence used for the answer."
        }
    }
}
