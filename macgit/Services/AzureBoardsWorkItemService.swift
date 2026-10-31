// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Azure DevOps Services work items of the remote's project (REST api-version 7.1).
/// `repository.hostURL` is the organization URL and `repository.owner` the project.
struct AzureBoardsWorkItemService: HostedIssueProviding {
    static let apiVersion = "7.1"
    /// Work item comments are still a preview API; pinned here so one place changes.
    static let commentsAPIVersion = "7.1-preview.4"
    /// The maximum `workitemsbatch` accepts; also one list page.
    static let batchSize = 200
    static let readScope = "a valid personal access token with the Work Items (Read) scope"
    static let writeScope = "a personal access token with the Work Items (Read & write) scope"

    private let httpClient: GitProviderHTTPClient
    private let decoder = JSONDecoder.hostedIssueDecoder()

    init(httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()) {
        self.httpClient = httpClient
    }

    func listIssues(
        repository: GitRepositoryIdentity,
        account: GitProviderAccount,
        token: GitProviderToken,
        filter: HostedIssueFilter,
        search: String,
        cursor: HostedIssueCursor?
    ) async throws -> HostedIssuePage {
        let states = try await stateCatalog(repository: repository, token: token)
        let ids: [Int]
        if case .workItemIDs(let remaining) = cursor {
            ids = remaining
        } else {
            let query = Self.wiql(filter: filter, search: search, closedStates: states.closedStateNames)
            let request = try jsonRequest(url: projectURL(repository, ["wiql"]), token: token, method: "POST", body: ["query": query])
            let (data, _) = try await send(request)
            ids = try decoder.decode(AzureWIQLResponse.self, from: data).workItems.map(\.id)
        }
        let pageIDs = Array(ids.prefix(Self.batchSize))
        let rest = Array(ids.dropFirst(Self.batchSize))
        guard !pageIDs.isEmpty else { return HostedIssuePage(items: [], next: nil) }

        let request = try jsonRequest(url: organizationURL(repository, ["wit", "workitemsbatch"]), token: token, method: "POST", body: [
            "ids": pageIDs,
            "fields": AzureWorkItemResponse.listFields,
        ])
        let (data, _) = try await send(request)
        let byID = Dictionary(
            try decoder.decode(AzureListResponse<AzureWorkItemResponse>.self, from: data).value.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // The batch endpoint does not keep the query's order.
        let items = pageIDs.compactMap { byID[$0]?.summary(repository: repository, states: states) }
        return HostedIssuePage(items: items, next: rest.isEmpty ? nil : .workItemIDs(rest))
    }

    func issueDetail(
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> HostedIssueDetail {
        let states = try await stateCatalog(repository: repository, token: token)
        let item = try await workItem(number, repository: repository, token: token)

        var comments: [HostedIssueComment] = []
        var commentsUnavailable = false
        do {
            let url = try projectURL(repository, ["workItems", String(number), "comments"],
                                     query: [URLQueryItem(name: "order", value: "asc")],
                                     apiVersion: Self.commentsAPIVersion)
            let (data, _) = try await send(AzureDevOpsProviderAuthService.apiRequest(url: url, token: token))
            comments = try decoder.decode(AzureCommentsResponse.self, from: data).comments.map(\.comment)
        } catch let error as HostedIssueError where error == .reauthorizationRequired {
            throw error
        } catch {
            commentsUnavailable = true
        }
        return HostedIssueDetail(
            summary: item.summary(repository: repository, states: states),
            body: item.fields.description ?? "",
            bodyFormat: .html,
            comments: comments,
            commentsUnavailable: commentsUnavailable
        )
    }

    func workItemTypes(repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> [String] {
        try await types(repository: repository, token: token).filter { !($0.isDisabled ?? false) }.map(\.name)
    }

    func createIssue(
        _ draft: HostedIssueDraft,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> HostedIssueSummary {
        guard let type = draft.workItemType, !type.isEmpty else {
            throw HostedIssueError.providerMessage("Choose a work item type.")
        }
        var operations: [[String: Any]] = [["op": "add", "path": "/fields/System.Title", "value": draft.title]]
        if !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            operations.append(["op": "add", "path": "/fields/System.Description", "value": HostedIssueHTMLText.html(fromPlainText: draft.body)])
        }
        let request = try patchRequest(url: projectURL(repository, ["workitems", "$" + type]), token: token, method: "POST", operations: operations)
        let (data, _) = try await send(request, write: true)
        let states = try await stateCatalog(repository: repository, token: token)
        return try decoder.decode(AzureWorkItemResponse.self, from: data).summary(repository: repository, states: states)
    }

    func addComment(
        _ body: String,
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        let url = try projectURL(repository, ["workItems", String(number), "comments"], apiVersion: Self.commentsAPIVersion)
        let request = try jsonRequest(url: url, token: token, method: "POST", body: ["text": HostedIssueHTMLText.html(fromPlainText: body)])
        _ = try await send(request, write: true)
    }

    func setState(
        _ state: HostedIssueState,
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        let item = try await workItem(number, repository: repository, token: token)
        let types = try await types(repository: repository, token: token)
        let type = item.fields.workItemType ?? ""
        let wanted: AzureStateCategory = state == .closed ? .completed : .proposed
        guard let target = types.first(where: { $0.name == type })?.states?.first(where: { $0.category == wanted }) else {
            throw HostedIssueError.closeUnavailable(state == .closed
                ? "\(type) work items have no Completed state, so Commit+ cannot close this one."
                : "\(type) work items have no Proposed state, so Commit+ cannot reopen this one.")
        }
        let request = try patchRequest(
            url: projectURL(repository, ["workitems", String(number)]),
            token: token,
            method: "PATCH",
            operations: [["op": "add", "path": "/fields/System.State", "value": target.name]]
        )
        _ = try await send(request, write: true)
    }

    // MARK: - Queries

    static func wiql(filter: HostedIssueFilter, search: String, closedStates: [String]) -> String {
        var clauses = ["[System.TeamProject] = @project"]
        let closedList = closedStates.map(quoted).joined(separator: ", ")
        switch filter.state {
        case .open where !closedStates.isEmpty: clauses.append("[System.State] NOT IN (\(closedList))")
        case .closed where !closedStates.isEmpty: clauses.append("[System.State] IN (\(closedList))")
        // No Completed or Removed states at all: every work item is open.
        case .closed: clauses.append("[System.Id] < 0")
        case .open, .all: break
        }
        switch filter.relationship {
        case .assignedToMe: clauses.append("[System.AssignedTo] = @Me")
        case .createdByMe: clauses.append("[System.CreatedBy] = @Me")
        case .all: break
        }
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let number = text.replacingOccurrences(of: "AB#", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if let id = Int(number) {
                clauses.append("[System.Id] = \(id)")
            } else {
                clauses.append("[System.Title] CONTAINS \(quoted(text))")
            }
        }
        return "SELECT [System.Id] FROM WorkItems WHERE " + clauses.joined(separator: " AND ")
            + " ORDER BY [System.ChangedDate] DESC"
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func stateCatalog(repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> AzureStateCatalog {
        AzureStateCatalog(types: try await types(repository: repository, token: token))
    }

    private func types(repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> [AzureWorkItemTypeResponse] {
        let (data, _) = try await send(AzureDevOpsProviderAuthService.apiRequest(url: projectURL(repository, ["workitemtypes"]), token: token))
        return try decoder.decode(AzureListResponse<AzureWorkItemTypeResponse>.self, from: data).value
    }

    private func workItem(_ id: Int, repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> AzureWorkItemResponse {
        let url = try projectURL(repository, ["workitems", String(id)])
        let (data, _) = try await send(AzureDevOpsProviderAuthService.apiRequest(url: url, token: token))
        return try decoder.decode(AzureWorkItemResponse.self, from: data)
    }

    // MARK: - Requests

    private func projectURL(_ repository: GitRepositoryIdentity, _ path: [String], query: [URLQueryItem] = [],
                            apiVersion: String = Self.apiVersion) throws -> URL {
        try url(repository.hostURL.appending(path: repository.owner).appending(path: "_apis/wit"), path, query: query, apiVersion: apiVersion)
    }

    private func organizationURL(_ repository: GitRepositoryIdentity, _ path: [String]) throws -> URL {
        try url(repository.hostURL.appending(path: "_apis"), path, query: [], apiVersion: Self.apiVersion)
    }

    private func url(_ base: URL, _ path: [String], query: [URLQueryItem], apiVersion: String) throws -> URL {
        var url = base
        for component in path { url = url.appending(path: component) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw HostedIssueError.notFound }
        components.queryItems = query + [URLQueryItem(name: "api-version", value: apiVersion)]
        guard let result = components.url else { throw HostedIssueError.notFound }
        return result
    }

    private func jsonRequest(url: URL, token: GitProviderToken, method: String, body: [String: Any]) throws -> URLRequest {
        var request = AzureDevOpsProviderAuthService.apiRequest(url: url, token: token)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private func patchRequest(url: URL, token: GitProviderToken, method: String, operations: [[String: Any]]) throws -> URLRequest {
        var request = AzureDevOpsProviderAuthService.apiRequest(url: url, token: token)
        request.httpMethod = method
        request.setValue("application/json-patch+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: operations, options: [.sortedKeys])
        return request
    }

    private func send(_ request: URLRequest, write: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await httpClient.data(for: request)
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        // 203 or an HTML page is how Azure DevOps answers a token it no longer accepts.
        if response.statusCode == 203 || ((200..<300).contains(response.statusCode) && contentType.contains("text/html")) {
            throw HostedIssueError.reauthorizationRequired
        }
        guard !(200..<300).contains(response.statusCode) else { return (data, response) }
        let message = (try? decoder.decode(AzureErrorResponse.self, from: data))?.message ?? ""
        switch response.statusCode {
        // The token already passed the organization check when it was connected, so a 401 or 403
        // here almost always means the PAT lacks the Work Items scope.
        case 401, 403:
            throw HostedIssueError.missingScope(write ? Self.writeScope : Self.readScope)
        case 404:
            throw HostedIssueError.notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw HostedIssueError.rateLimited(retryAfter: retryAfter.map { Date(timeIntervalSinceNow: $0) })
        default:
            throw HostedIssueError.providerMessage(
                message.isEmpty ? "Azure DevOps work item request failed (HTTP \(response.statusCode))." : message
            )
        }
    }
}

/// Azure HTML shown as text: tags dropped, images never loaded, entities decoded.
enum HostedIssueHTMLText {
    static func plainText(fromHTML html: String) -> String {
        var text = html
        let replacements: [(String, String)] = [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|h[1-6]|tr|pre|blockquote)>", "\n"),
            ("(?i)<li[^>]*>", "\n• "),
            ("(?is)<(script|style)[^>]*>.*?</\\1>", ""),
            ("(?s)<[^>]+>", ""),
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func html(fromPlainText text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let range = Range(match.range, in: result),
                      let hexRange = Range(match.range(at: 1), in: result),
                      let digitsRange = Range(match.range(at: 2), in: result),
                      let code = UInt32(result[digitsRange], radix: result[hexRange].isEmpty ? 10 : 16),
                      let scalar = Unicode.Scalar(code) else { continue }
                result.replaceSubrange(range, with: String(Character(scalar)))
            }
        }
        // Last, so "&amp;lt;" stays "&lt;".
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}

private enum AzureStateCategory: String, Decodable {
    case proposed = "Proposed"
    case inProgress = "InProgress"
    case resolved = "Resolved"
    case completed = "Completed"
    case removed = "Removed"
    case other

    init(from decoder: Decoder) throws {
        self = AzureStateCategory(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
}

private struct AzureWorkItemTypeResponse: Decodable {
    struct State: Decodable {
        var name: String
        var category: AzureStateCategory?
    }

    var name: String
    var isDisabled: Bool?
    var states: [State]?
}

private struct AzureStateCatalog {
    private var closedByType: [String: Set<String>] = [:]
    private(set) var closedStateNames: [String] = []

    init(types: [AzureWorkItemTypeResponse]) {
        var names = Set<String>()
        for type in types {
            let closed = Set((type.states ?? []).filter { $0.category == .completed || $0.category == .removed }.map(\.name))
            closedByType[type.name] = closed
            names.formUnion(closed)
        }
        closedStateNames = names.sorted()
    }

    func isClosed(state: String, type: String) -> Bool {
        closedByType[type]?.contains(state) ?? closedStateNames.contains(state)
    }
}

private struct AzureListResponse<Value: Decodable>: Decodable {
    var value: [Value]
}

private struct AzureWIQLResponse: Decodable {
    struct Reference: Decodable { var id: Int }
    var workItems: [Reference]
}

private struct AzureErrorResponse: Decodable {
    var message: String
}

private struct AzureIdentity: Decodable {
    var id: String?
    var displayName: String?
    var uniqueName: String?
    var imageUrl: URL?

    var person: HostedIssuePerson {
        HostedIssuePerson(id: id ?? uniqueName ?? displayName ?? "", displayName: displayName ?? uniqueName ?? "", avatarURL: nil)
    }
}

private struct AzureWorkItemResponse: Decodable {
    static let listFields = [
        "System.Id", "System.Title", "System.State", "System.WorkItemType", "System.CreatedBy",
        "System.AssignedTo", "System.Tags", "System.CreatedDate", "System.ChangedDate",
    ]

    struct Fields: Decodable {
        var title: String?
        var state: String?
        var workItemType: String?
        var createdBy: AzureIdentity?
        var assignedTo: AzureIdentity?
        var tags: String?
        var createdDate: Date?
        var changedDate: Date?
        var description: String?

        enum CodingKeys: String, CodingKey {
            case title = "System.Title"
            case state = "System.State"
            case workItemType = "System.WorkItemType"
            case createdBy = "System.CreatedBy"
            case assignedTo = "System.AssignedTo"
            case tags = "System.Tags"
            case createdDate = "System.CreatedDate"
            case changedDate = "System.ChangedDate"
            case description = "System.Description"
        }
    }

    var id: Int
    var fields: Fields

    func summary(repository: GitRepositoryIdentity, states: AzureStateCatalog) -> HostedIssueSummary {
        let state = fields.state ?? ""
        let type = fields.workItemType ?? ""
        return HostedIssueSummary(
            number: id,
            title: fields.title ?? "",
            state: states.isClosed(state: state, type: type) ? .closed : .open,
            stateName: state.isEmpty ? nil : state,
            workItemType: type.isEmpty ? nil : type,
            author: fields.createdBy?.person,
            assignees: fields.assignedTo.map { [$0.person] } ?? [],
            labels: (fields.tags ?? "").split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { HostedIssueLabel(name: $0, color: nil) },
            createdAt: fields.createdDate,
            updatedAt: fields.changedDate,
            webURL: repository.hostURL.appending(path: repository.owner).appending(path: "_workitems/edit/\(id)")
        )
    }
}

private struct AzureCommentsResponse: Decodable {
    struct Comment: Decodable {
        var id: Int
        var text: String?
        var createdBy: AzureIdentity?
        var createdDate: Date?

        var comment: HostedIssueComment {
            HostedIssueComment(id: String(id), author: createdBy?.person, body: text ?? "", format: .html, createdAt: createdDate)
        }
    }

    var comments: [Comment]
}
