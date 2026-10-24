// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Where Jira REST requests are sent. Scoped API tokens only work through Atlassian's gateway.
enum JiraAPIBase: Codable, Equatable, Sendable {
    case site
    case gateway(cloudID: String)
}

/// Non-secret metadata for the Jira Cloud site connected on this Mac. The token lives in the Keychain.
struct JiraConnection: Codable, Equatable, Identifiable, Sendable {
    var macgitUID: String
    var siteURL: URL
    var email: String
    var accountID: String
    var displayName: String
    var apiBase: JiraAPIBase
    /// The custom field holding sprints; nil on sites without Jira Software.
    var sprintFieldID: String?
    var needsReconnect = false
    var connectedAt = Date()

    var id: String { "\(macgitUID):\(siteHost):\(accountID)" }

    var siteHost: String { siteURL.host(percentEncoded: false)?.lowercased() ?? siteURL.absoluteString }

    var apiBaseURL: URL {
        switch apiBase {
        case .site:
            siteURL
        case .gateway(let cloudID):
            URL(string: "https://api.atlassian.com/ex/jira")!.appending(path: cloudID)
        }
    }

    var supportsSprints: Bool { sprintFieldID != nil }

    func browseURL(for issueKey: String) -> URL {
        siteURL.appending(path: "browse").appending(path: issueKey)
    }
}

struct JiraCredential: Equatable, Sendable {
    var email: String
    var token: String

    var authorizationHeader: String {
        "Basic " + Data("\(email):\(token)".utf8).base64EncodedString()
    }
}

enum JiraStatusCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case toDo = "new"
    case inProgress = "indeterminate"
    case done

    var title: String {
        switch self {
        case .toDo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}

struct JiraSprintRef: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var name: String
    var state: String

    var isOpen: Bool { state == "active" || state == "future" }
}

struct JiraIssue: Identifiable, Equatable, Sendable {
    var id: String
    var key: String
    var summary: String
    var statusName: String
    var statusCategory: JiraStatusCategory?
    var issueTypeName: String
    var priorityName: String?
    var projectKey: String
    var projectName: String
    var updated: Date?
    var sprints: [JiraSprintRef]

    /// The sprint shown on the row: the active one, else the next open one, else the most recent.
    var displaySprint: JiraSprintRef? {
        sprints.first { $0.state == "active" } ?? sprints.first { $0.isOpen } ?? sprints.last
    }
}

struct JiraIssuePage: Equatable, Sendable {
    var issues: [JiraIssue]
    var nextPageToken: String?
}

struct JiraIssueFilter: Codable, Equatable, Sendable {
    enum SprintScope: Codable, Hashable, Sendable {
        case openSprints
        case sprint(id: Int, name: String)
        case backlog
        case any
    }

    var sprintScope: SprintScope = .openSprints
    /// Empty means any status.
    var statusCategories: Set<JiraStatusCategory> = [.toDo, .inProgress]
    /// Empty means any project.
    var projectKeys: Set<String> = []
    /// Empty means any issue type. Names, because team-managed projects use per-project type ids.
    var issueTypeNames: Set<String> = []
    /// Not persisted: search text applies only to the current session.
    var searchText = ""

    static let `default` = JiraIssueFilter()

    var isDefault: Bool {
        var withoutSearch = self
        withoutSearch.searchText = ""
        return withoutSearch == .default
    }

    private enum CodingKeys: String, CodingKey {
        case sprintScope, statusCategories, projectKeys, issueTypeNames
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sprintScope = try container.decode(SprintScope.self, forKey: .sprintScope)
        statusCategories = try container.decode(Set<JiraStatusCategory>.self, forKey: .statusCategories)
        projectKeys = try container.decode(Set<String>.self, forKey: .projectKeys)
        issueTypeNames = try container.decode(Set<String>.self, forKey: .issueTypeNames)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sprintScope, forKey: .sprintScope)
        try container.encode(statusCategories, forKey: .statusCategories)
        try container.encode(projectKeys, forKey: .projectKeys)
        try container.encode(issueTypeNames, forKey: .issueTypeNames)
    }
}

enum JiraError: LocalizedError, Equatable {
    case unsupportedSite
    case invalidCredentials
    case needsReconnect
    case forbidden
    case rateLimited(retryAfter: Int?)
    case unreachable
    case invalidResponse
    case invalidQuery
    case notSignedIn
    case notConnected
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSite:
            "Only Jira Cloud sites (https://your-site.atlassian.net) are supported."
        case .invalidCredentials:
            "Jira did not accept this email or API token."
        case .needsReconnect:
            "Jira no longer accepts the saved API token. Reconnect Jira in Settings → Integrations."
        case .forbidden:
            "Your Jira account does not have permission to view these issues."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                "Jira is busy. Try again in \(retryAfter) seconds."
            } else {
                "Jira is busy. Try again in a moment."
            }
        case .unreachable:
            "The Jira site could not be reached. Check the site address and your network connection."
        case .invalidResponse:
            "The Jira site did not respond as Jira Cloud."
        case .invalidQuery:
            "Jira could not run this filter."
        case .notSignedIn:
            "Sign in to Commit+ to connect Jira."
        case .notConnected:
            "No Jira site is connected."
        case .storage(let message):
            message
        }
    }
}

enum JiraSiteNormalizer {
    /// Accepts `acme`, `acme.atlassian.net`, or `https://acme.atlassian.net[/...]` and returns the site root.
    static func normalize(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JiraError.unsupportedSite }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else if trimmed.contains(".") || trimmed.contains("/") {
            candidate = "https://" + trimmed
        } else {
            candidate = "https://\(trimmed).atlassian.net"
        }

        guard let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              host.hasSuffix(".atlassian.net"),
              let name = host.split(separator: ".").first,
              host == "\(name).atlassian.net",
              name.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }),
              let url = URL(string: "https://\(host)") else {
            throw JiraError.unsupportedSite
        }
        return url
    }
}
