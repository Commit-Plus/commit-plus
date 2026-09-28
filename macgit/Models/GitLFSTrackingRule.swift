// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSTrackingRule: Identifiable, Sendable {
    let pattern: String
    let source: String
    let excluded: Bool
    var id: String { source + "\0" + pattern + "\0" + String(excluded) }
    var canRemove: Bool { source == ".gitattributes" && !excluded && !pattern.hasPrefix("\"") }

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
