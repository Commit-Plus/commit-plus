// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The issue tracker that belongs to a recognized remote's provider.
enum HostedIssueProvider: String, Codable, Equatable {
    case github
    case gitlab
    case bitbucket
    case azureBoards

    init(_ kind: GitProviderKind) {
        switch kind {
        case .github: self = .github
        case .gitlab: self = .gitlab
        case .bitbucket: self = .bitbucket
        case .azureDevOps: self = .azureBoards
        }
    }

    var sidebarTitle: String {
        switch self {
        case .github: "GitHub Issues"
        case .gitlab: "GitLab Issues"
        case .bitbucket: "Bitbucket Issues"
        case .azureBoards: "Azure Boards"
        }
    }

    /// Asset-catalog image shared with the repository picker.
    var iconName: String {
        switch self {
        case .github: "github"
        case .gitlab: "gitlab"
        case .bitbucket: "bitbucket"
        case .azureBoards: "azure"
        }
    }

    var accountKind: GitProviderKind {
        switch self {
        case .github: .github
        case .gitlab: .gitlab
        case .bitbucket: .bitbucket
        case .azureBoards: .azureDevOps
        }
    }

    /// `AB#42` is how Azure DevOps links work items from commits and pull requests.
    func reference(for number: Int) -> String {
        self == .azureBoards ? "AB#\(number)" : "#\(number)"
    }

    /// Azure work items belong to a project; the other trackers belong to the repository.
    var supportsWorkItemTypes: Bool { self == .azureBoards }
}

enum HostedIssueState: String, Codable, Equatable {
    case open
    case closed
}

enum HostedIssueStateFilter: String, Codable, CaseIterable, Identifiable {
    case open
    case closed
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .closed: "Closed"
        case .all: "All"
        }
    }
}

enum HostedIssueRelationship: String, Codable, CaseIterable, Identifiable {
    case all
    case assignedToMe
    case createdByMe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .assignedToMe: "Assigned to Me"
        case .createdByMe: "Created by Me"
        }
    }
}

/// Persisted per repository and remote; search text is never part of it.
struct HostedIssueFilter: Codable, Equatable {
    var state: HostedIssueStateFilter = .open
    var relationship: HostedIssueRelationship = .all

    static let `default` = HostedIssueFilter()

    var isDefault: Bool { self == .default }
}

struct HostedIssuePerson: Codable, Equatable, Hashable {
    var id: String
    var displayName: String
    var avatarURL: URL?
}

struct HostedIssueLabel: Codable, Equatable, Hashable {
    var name: String
    /// Hex without `#`, when the provider has one.
    var color: String?
}

enum HostedIssueTextFormat: String, Codable, Equatable {
    case markdown
    case html
}

struct HostedIssueSummary: Identifiable, Equatable, Codable {
    var id: Int { number }
    var number: Int
    var title: String
    var state: HostedIssueState
    /// The provider's own state name when it says more than open/closed, such as "On hold" or "Active".
    var stateName: String?
    var workItemType: String?
    var author: HostedIssuePerson?
    var assignees: [HostedIssuePerson]
    var labels: [HostedIssueLabel]
    var createdAt: Date?
    var updatedAt: Date?
    var webURL: URL?
}

struct HostedIssueComment: Identifiable, Equatable, Codable {
    var id: String
    var author: HostedIssuePerson?
    var body: String
    var format: HostedIssueTextFormat
    var createdAt: Date?
}

struct HostedIssueDetail: Equatable, Codable {
    var summary: HostedIssueSummary
    var body: String
    var bodyFormat: HostedIssueTextFormat
    var comments: [HostedIssueComment]
    /// Set when the comments endpoint failed but the issue itself loaded.
    var commentsUnavailable = false
}

/// Where the next page starts. Each provider paginates differently.
enum HostedIssueCursor: Equatable {
    case page(Int)
    case url(URL)
    /// Azure answers a query with every matching ID up front; details are fetched in chunks.
    case workItemIDs([Int])
}

struct HostedIssuePage: Equatable {
    var items: [HostedIssueSummary]
    var next: HostedIssueCursor?
}

struct HostedIssueDraft: Equatable {
    var title: String
    var body: String
    var workItemType: String?
}

enum HostedIssueError: LocalizedError, Equatable {
    case trackerDisabled
    /// A phrase completing "The connected account needs …", such as "the Work Items scope".
    case missingScope(String)
    case organizationAccessRequired
    case reauthorizationRequired
    case rateLimited(retryAfter: Date?)
    case notFound
    case closeUnavailable(String)
    /// The saved account lacks something the issue API needs, fixed by editing it in Settings → Connections.
    case accountUpdateRequired(String)
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .trackerDisabled:
            "Issues are turned off for this repository."
        case .missingScope(let requirement):
            "The connected account needs \(requirement)."
        case .organizationAccessRequired:
            "The repository's organization has not granted Commit+ access."
        case .reauthorizationRequired:
            "The Git provider account needs to be connected again."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "The provider is busy. Try again \(retryAfter.formatted(.relative(presentation: .named)))."
            } else {
                "The provider is busy. Try again in a moment."
            }
        case .notFound:
            "The issue or repository could not be found with the connected account."
        case .closeUnavailable(let reason), .accountUpdateRequired(let reason):
            reason
        case .providerMessage(let message):
            message
        }
    }
}

protocol HostedIssueProviding {
    func listIssues(
        repository: GitRepositoryIdentity,
        account: GitProviderAccount,
        token: GitProviderToken,
        filter: HostedIssueFilter,
        search: String,
        cursor: HostedIssueCursor?
    ) async throws -> HostedIssuePage

    func issueDetail(
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> HostedIssueDetail

    func workItemTypes(repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> [String]

    func createIssue(
        _ draft: HostedIssueDraft,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> HostedIssueSummary

    func addComment(
        _ body: String,
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws

    func setState(
        _ state: HostedIssueState,
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws
}

extension HostedIssueProviding {
    func workItemTypes(repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> [String] {
        []
    }
}

extension JSONDecoder {
    /// ISO 8601 with or without fractional seconds. GitLab sends milliseconds and Azure sends
    /// up to seven fractional digits, which `ISO8601DateFormatter` rejects, so they are cut to three.
    static func hostedIssueDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = parseHostedIssueDate(value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(value)"))
        }
        return decoder
    }
}

func parseHostedIssueDate(_ value: String) -> Date? {
    let plain = ISO8601DateFormatter()
    if let date = plain.date(from: value) { return date }
    var trimmed = value
    if let dot = value.firstIndex(of: ".") {
        let fractionEnd = value[dot...].dropFirst().firstIndex { !$0.isNumber } ?? value.endIndex
        let digits = value[value.index(after: dot)..<fractionEnd]
        trimmed = String(value[..<dot]) + "." + String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            + String(value[fractionEnd...])
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: trimmed)
}
