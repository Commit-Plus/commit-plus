// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Suggests `<KEY>-<slug>` branch names for Jira issues, e.g. `PROJ-123-fix-login-crash`.
enum JiraBranchNameSuggester {
    static let maxLength = 60

    static func name(key: String, summary: String) -> String {
        let slug = slug(from: summary)
        guard !slug.isEmpty else { return key }
        let full = "\(key)-\(slug)"
        guard full.count > maxLength else { return full }

        // Cut at a word boundary so the name never ends mid-word, but always keep the key.
        let limited = String(full.prefix(maxLength))
        guard let lastHyphen = limited.lastIndex(of: "-"),
              limited.distance(from: limited.startIndex, to: lastHyphen) > key.count else {
            return key
        }
        return String(limited[..<lastHyphen])
    }

    private static func slug(from summary: String) -> String {
        // "đ" is a separate letter, not "d" with a diacritic, so stripping marks leaves it alone.
        let latin = summary
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .applyingTransform(.toLatin, reverse: false) ?? summary
        let folded = (latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin).lowercased()
        var slug = ""
        for character in folded {
            if character.isASCII, character.isLetter || character.isNumber {
                slug.append(character)
            } else if !slug.isEmpty, slug.last != "-" {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }
}

/// How a branch is started from a Jira issue: a plain branch, or a Git Flow topic.
enum JiraBranchTarget: Hashable, Identifiable {
    case plainBranch
    case gitFlow(GitFlowTopicKind)

    var id: String {
        switch self {
        case .plainBranch: "branch"
        case .gitFlow(let kind): kind.rawValue
        }
    }

    var title: String {
        switch self {
        case .plainBranch: "New Branch…"
        case .gitFlow(let kind): "Start \(kind.displayName)…"
        }
    }

    /// Release topics are named after versions, not issues, so they are not offered.
    static func options(gitFlowEnabled: Bool) -> [JiraBranchTarget] {
        guard gitFlowEnabled else { return [.plainBranch] }
        return [.gitFlow(.feature), .gitFlow(.bugfix), .gitFlow(.hotfix), .plainBranch]
    }

    static func suggested(forIssueType issueTypeName: String, gitFlowEnabled: Bool) -> JiraBranchTarget {
        guard gitFlowEnabled else { return .plainBranch }
        switch issueTypeName.lowercased() {
        case "bug", "defect": return .gitFlow(.bugfix)
        default: return .gitFlow(.feature)
        }
    }
}
