// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSTrackingRule: Identifiable, Sendable {
    let pattern: String
    let source: String
    let excluded: Bool
    var id: String { source + "\0" + pattern + "\0" + String(excluded) }
    var canRemove: Bool { source == ".gitattributes" && !excluded && !pattern.hasPrefix("\"") }

    var patternKind: String {
        var escaped = false
        for character in pattern {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if "*?[".contains(character) { return "Pattern" }
        }
        return "Filename"
    }

    /// Match the stored attributes token exactly, including escaped glob characters.
    static func removingRootRule(_ pattern: String, literal: Bool, from contents: String) -> String {
        let token = literal ? pattern.reduce(into: "") { result, character in
            if "*?[]".contains(character) { result.append("\\") }
            result.append(character)
        }.replacingOccurrences(of: " ", with: "[[:space:]]") : pattern
        return contents.components(separatedBy: "\n").filter { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
            return !(fields.first.map(String.init) == token && fields.dropFirst().contains("filter=lfs"))
        }.joined(separator: "\n")
    }

    /// Presentation only. Git remains authoritative for effective attributes and edits.
    static func displayRules(_ listing: String) -> [Self] {
        var excluded = false
        var result: [Self] = []
        var seen = Set<String>()
        for line in listing.split(separator: "\n") {
            if line == "Listing excluded patterns" { excluded = true; continue }
            guard line.hasPrefix("    "), line.hasSuffix(")"),
                  let separator = line.range(of: " (", options: .backwards) else { continue }
            let pattern = String(line.dropFirst(4)[..<separator.lowerBound])
            let source = String(line[separator.upperBound...].dropLast())
            let rule = Self(pattern: pattern, source: source, excluded: excluded)
            if seen.insert(rule.id).inserted { result.append(rule) }
        }
        return result
    }
}
