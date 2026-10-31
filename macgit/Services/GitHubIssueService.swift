// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// GitHub.com and GitHub Enterprise Server issues through the REST API.
struct GitHubIssueService: HostedIssueProviding {
    static let pageSize = 30

    private let httpClient: GitProviderHTTPClient
    private let apiBaseURL: URL
    private let decoder: JSONDecoder

    init(
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        apiBaseURL: URL = URL(string: "https://api.github.com")!
    ) {
        self.httpClient = httpClient
        self.apiBaseURL = apiBaseURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func listIssues(
        repository: GitRepositoryIdentity,
        account: GitProviderAccount,
        token: GitProviderToken,
        filter: HostedIssueFilter,
        search: String,
        cursor: HostedIssueCursor?
    ) async throws -> HostedIssuePage {
        let page: Int = if case .page(let value) = cursor { value } else { 1 }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // The issues endpoint has no text search; the search endpoint does, with a lower rate limit.
        if !query.isEmpty {
            var terms = ["repo:\(repository.owner)/\(repository.name)", "is:issue"]
            switch filter.state {
            case .open: terms.append("is:open")
            case .closed: terms.append("is:closed")
            case .all: break
            }
            switch filter.relationship {
            case .assignedToMe: terms.append("assignee:\(account.username)")
            case .createdByMe: terms.append("author:\(account.username)")
            case .all: break
            }
            terms.append(query)
            let url = try url(apiURL(for: repository).appendingPathComponent("search/issues"), query: [
                "q": terms.joined(separator: " "),
                "sort": "updated",
                "order": "desc",
                "per_page": String(Self.pageSize),
                "page": String(page),
            ])
            let (data, response) = try await send(makeRequest(url: url, token: token))
            let result = try decoder.decode(GitHubIssueSearchResponse.self, from: data)
            return HostedIssuePage(
                items: result.items.filter { $0.pullRequest == nil }.map(\.summary),
                next: hasNextPage(response) ? .page(page + 1) : nil
            )
        }

        var items: [String: String] = [
            "state": filter.state.rawValue,
            "sort": "updated",
            "direction": "desc",
            "per_page": String(Self.pageSize),
            "page": String(page),
        ]
        switch filter.relationship {
        case .assignedToMe: items["assignee"] = account.username
        case .createdByMe: items["creator"] = account.username
        case .all: break
        }
        let url = try url(issuesURL(for: repository), query: items)
        let (data, response) = try await send(makeRequest(url: url, token: token))
        // The issues endpoint also returns pull requests.
        let issues = try decoder.decode([GitHubIssueResponse].self, from: data).filter { $0.pullRequest == nil }
        return HostedIssuePage(items: issues.map(\.summary), next: hasNextPage(response) ? .page(page + 1) : nil)
    }

    func issueDetail(
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> HostedIssueDetail {
        let issueURL = issuesURL(for: repository).appendingPathComponent(String(number))
        let (data, _) = try await send(makeRequest(url: issueURL, token: token))
        let issue = try decoder.decode(GitHubIssueResponse.self, from: data)

        var comments: [HostedIssueComment] = []
        var commentsUnavailable = false
        var page = 1
        do {
            while page <= 10 {
                let url = try url(issueURL.appendingPathComponent("comments"), query: [
                    "per_page": "100",
                    "page": String(page),
                ])
                let (data, response) = try await send(makeRequest(url: url, token: token))
                comments += try decoder.decode([GitHubIssueCommentResponse].self, from: data).map(\.comment)
                guard hasNextPage(response) else { break }
                page += 1
            }
        } catch let error as HostedIssueError where error == .reauthorizationRequired {
            throw error
        } catch {
            commentsUnavailable = true
        }
        return HostedIssueDetail(
            summary: issue.summary,
            body: issue.body ?? "",
            bodyFormat: .markdown,
            comments: comments,
            commentsUnavailable: commentsUnavailable
        )
    }

    func createIssue(
        _ draft: HostedIssueDraft,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> HostedIssueSummary {
        let request = try makeJSONRequest(
            url: issuesURL(for: repository),
            token: token,
            method: "POST",
            body: ["title": draft.title, "body": draft.body]
        )
        let (data, _) = try await send(request, write: true)
        return try decoder.decode(GitHubIssueResponse.self, from: data).summary
    }

    func addComment(
        _ body: String,
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        let request = try makeJSONRequest(
            url: issuesURL(for: repository).appendingPathComponent(String(number)).appendingPathComponent("comments"),
            token: token,
            method: "POST",
            body: ["body": body]
        )
        _ = try await send(request, write: true)
    }

    func setState(
        _ state: HostedIssueState,
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        let request = try makeJSONRequest(
            url: issuesURL(for: repository).appendingPathComponent(String(number)),
            token: token,
            method: "PATCH",
            body: ["state": state.rawValue]
        )
        _ = try await send(request, write: true)
    }

    // MARK: - Requests

    private func apiURL(for repository: GitRepositoryIdentity) -> URL {
        let host = GitProviderHost(kind: .github, baseURL: repository.hostURL)
        return host.normalized.baseURL == GitProviderHost.githubDotCom.baseURL ? apiBaseURL : host.apiURL
    }

    private func issuesURL(for repository: GitRepositoryIdentity) -> URL {
        apiURL(for: repository)
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("issues")
    }

    private func url(_ base: URL, query: [String: String]) throws -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw HostedIssueError.notFound }
        return url
    }

    private func makeRequest(url: URL, token: GitProviderToken) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeJSONRequest(
        url: URL,
        token: GitProviderToken,
        method: String,
        body: [String: String]
    ) throws -> URLRequest {
        var request = makeRequest(url: url, token: token)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func send(_ request: URLRequest, write: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await httpClient.data(for: request)
        guard !(200..<300).contains(response.statusCode) else { return (data, response) }
        throw Self.error(for: response, data: data, write: write, decoder: decoder)
    }

    private func hasNextPage(_ response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: "Link")?
            .split(separator: ",")
            .contains { $0.range(of: "rel=\"next\"") != nil } ?? false
    }

    static func error(for response: HTTPURLResponse, data: Data, write: Bool, decoder: JSONDecoder) -> HostedIssueError {
        let message = (try? decoder.decode(GitHubIssueErrorResponse.self, from: data).message) ?? ""
        let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining")
        if response.statusCode == 429 || (response.statusCode == 403 && (remaining == "0" || message.localizedCaseInsensitiveContains("rate limit"))) {
            if let retryAfter = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) {
                return .rateLimited(retryAfter: Date(timeIntervalSinceNow: retryAfter))
            }
            let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: reset.map(Date.init(timeIntervalSince1970:)))
        }
        switch response.statusCode {
        case 401:
            return .reauthorizationRequired
        case 403 where message.localizedCaseInsensitiveContains("OAuth App access restrictions")
            || message.localizedCaseInsensitiveContains("SAML"):
            return .organizationAccessRequired
        case 403 where write, 404 where write:
            return .missingScope("write access to this repository")
        case 404:
            return .notFound
        case 410:
            return .trackerDisabled
        default:
            return .providerMessage(message.isEmpty ? "GitHub issue request failed (HTTP \(response.statusCode))." : message)
        }
    }
}

private struct GitHubIssueErrorResponse: Decodable {
    var message: String
}

private struct GitHubIssueSearchResponse: Decodable {
    var items: [GitHubIssueResponse]
}

private struct GitHubIssueUser: Decodable {
    var login: String
    var avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }

    var person: HostedIssuePerson {
        HostedIssuePerson(id: login, displayName: login, avatarURL: avatarURL)
    }
}

private struct GitHubIssueResponse: Decodable {
    struct Label: Decodable {
        var name: String
        var color: String?
    }

    struct PullRequestMarker: Decodable {}

    var number: Int
    var title: String
    var state: String
    var stateReason: String?
    var body: String?
    var htmlURL: URL?
    var user: GitHubIssueUser?
    var assignees: [GitHubIssueUser]?
    var labels: [Label]?
    var createdAt: Date?
    var updatedAt: Date?
    var pullRequest: PullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case number, title, state, body, user, assignees, labels
        case stateReason = "state_reason"
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case pullRequest = "pull_request"
    }

    var summary: HostedIssueSummary {
        HostedIssueSummary(
            number: number,
            title: title,
            state: state == "closed" ? .closed : .open,
            stateName: stateReason == "not_planned" ? "Not planned" : nil,
            workItemType: nil,
            author: user?.person,
            assignees: assignees?.map(\.person) ?? [],
            labels: labels?.map { HostedIssueLabel(name: $0.name, color: $0.color) } ?? [],
            createdAt: createdAt,
            updatedAt: updatedAt,
            webURL: htmlURL
        )
    }
}

private struct GitHubIssueCommentResponse: Decodable {
    var id: Int
    var body: String?
    var user: GitHubIssueUser?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, body, user
        case createdAt = "created_at"
    }

    var comment: HostedIssueComment {
        HostedIssueComment(id: String(id), author: user?.person, body: body ?? "", format: .markdown, createdAt: createdAt)
    }
}
