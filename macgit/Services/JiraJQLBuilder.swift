// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Builds JQL from a typed filter. Every value is quoted, so user input cannot change the query structure.
enum JiraJQLBuilder {
    static func jql(
        for filter: JiraIssueFilter,
        supportsSprints: Bool,
        includeKeyClause: Bool = true
    ) -> String {
        var clauses = ["assignee = currentUser()"]

        if supportsSprints {
            switch filter.sprintScope {
            case .openSprints: clauses.append("sprint in openSprints()")
            case .sprint(let id, _): clauses.append("sprint = \(id)")
            case .backlog: clauses.append("sprint is EMPTY")
            case .any: break
            }
        }

        if !filter.statusCategories.isEmpty {
            let categories = JiraStatusCategory.allCases
                .filter(filter.statusCategories.contains)
                .map { quoted($0.title) }
            clauses.append("statusCategory in (\(categories.joined(separator: ", ")))")
        }
        if !filter.projectKeys.isEmpty {
            clauses.append("project in (\(filter.projectKeys.sorted().map(quoted).joined(separator: ", ")))")
        }
        if !filter.issueTypeNames.isEmpty {
            clauses.append("issuetype in (\(filter.issueTypeNames.sorted().map(quoted).joined(separator: ", ")))")
        }
        if let search = searchClause(for: filter.searchText, includeKeyClause: includeKeyClause) {
            clauses.append(search)
        }

        return clauses.joined(separator: " AND ") + " ORDER BY updated DESC"
    }

    /// Whether the search text looks like an issue key, which Jira matches exactly instead of by text.
    static func issueKey(in searchText: String) -> String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard candidate.range(of: "^[A-Z][A-Z0-9_]+-[0-9]+$", options: .regularExpression) != nil else { return nil }
        return candidate
    }

    private static func searchClause(for searchText: String, includeKeyClause: Bool) -> String? {
        var parts: [String] = []
        let terms = textSearchTerms(searchText)
        if !terms.isEmpty {
            parts.append("summary ~ \(quoted(terms))")
        }
        if includeKeyClause, let key = issueKey(in: searchText) {
            parts.append("key = \(quoted(key))")
        }
        switch parts.count {
        case 0: return nil
        case 1: return parts[0]
        default: return "(\(parts.joined(separator: " OR ")))"
        }
    }

    /// Text search is Lucene-backed; its operator characters are dropped rather than escaped.
    private static func textSearchTerms(_ searchText: String) -> String {
        let reserved = Set("+-&|!(){}[]^~*?\\:\"'/")
        let cleaned = String(searchText.map { reserved.contains($0) ? " " : $0 })
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return "\"\(escaped)\""
    }
}
