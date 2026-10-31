// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// GitLab.com and self-managed GitLab issues through the v4 REST API.
struct GitLabIssueService: HostedIssueProviding {
    static let pageSize = 30

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
        let page: Int = if case .page(let value) = cursor { value } else { 1 }
        var query = [
            URLQueryItem(name: "order_by", value: "updated_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: String(Self.pageSize)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        switch filter.state {
        case .open: query.append(URLQueryItem(name: "state", value: "opened"))
        case .closed: query.append(URLQueryItem(name: "state", value: "closed"))
        case .all: break
        }
        let scope = switch filter.relationship {
        case .all: "all"
        case .assignedToMe: "assigned_to_me"
        case .createdByMe: "created_by_me"
        }
        query.append(URLQueryItem(name: "scope", value: scope))
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            // A bare number is an IID; GitLab's text search does not match it.
            if let iid = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))) {
                query.append(URLQueryItem(name: "iids[]", value: String(iid)))
            } else {
                query.append(URLQueryItem(name: "search", value: text))
            }
        }
        let url = try projectURL(repository, ["issues"], query: query)
        let (data, response) = try await send(makeRequest(url: url, token: token))
        let issues = try decoder.decode([GitLabIssueResponse].self, from: data)
        let nextPage = response.value(forHTTPHeaderField: "X-Next-Page").flatMap(Int.init)
        return HostedIssuePage(items: issues.map(\.summary), next: nextPage.map(HostedIssueCursor.page))
    }

    func issueDetail(
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> HostedIssueDetail {
        let (data, _) = try await send(makeRequest(url: projectURL(repository, ["issues", String(number)]), token: token))
        let issue = try decoder.decode(GitLabIssueResponse.self, from: data)

        var comments: [HostedIssueComment] = []
        var commentsUnavailable = false
        var page = 1
        do {
            while page <= 10 {
                let url = try projectURL(repository, ["issues", String(number), "notes"], query: [
                    URLQueryItem(name: "sort", value: "asc"),
                    URLQueryItem(name: "order_by", value: "created_at"),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page)),
                ])
                let (data, response) = try await send(makeRequest(url: url, token: token))
                comments += try decoder.decode([GitLabIssueNoteResponse].self, from: data)
                    .filter { !$0.system }
                    .map(\.comment)
                guard let next = response.value(forHTTPHeaderField: "X-Next-Page").flatMap(Int.init) else { break }
                page = next
            }
        } catch let error as HostedIssueError where error == .reauthorizationRequired {
            throw error
        } catch {
            commentsUnavailable = true
        }
        return HostedIssueDetail(
            summary: issue.summary,
            body: issue.description ?? "",
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
            url: projectURL(repository, ["issues"]),
            token: token,
            method: "POST",
            body: ["title": draft.title, "description": draft.body]
        )
        let (data, _) = try await send(request, write: true)
        return try decoder.decode(GitLabIssueResponse.self, from: data).summary
    }

    func addComment(
        _ body: String,
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        let request = try makeJSONRequest(
            url: projectURL(repository, ["issues", String(number), "notes"]),
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
            url: projectURL(repository, ["issues", String(number)]),
            token: token,
            method: "PUT",
            body: ["state_event": state == .closed ? "close" : "reopen"]
        )
        _ = try await send(request, write: true)
    }

    // MARK: - Requests

    private func projectURL(_ repository: GitRepositoryIdentity, _ path: [String], query: [URLQueryItem] = []) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let project = "\(repository.owner)/\(repository.name)".addingPercentEncoding(withAllowedCharacters: allowed),
              var components = URLComponents(url: repository.hostURL, resolvingAgainstBaseURL: false) else {
            throw HostedIssueError.notFound
        }
        let base = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.map { "/\($0)" }.joined()
        components.percentEncodedPath = (base.isEmpty ? "" : "/" + base) + "/api/v4/projects/\(project)\(suffix)"
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw HostedIssueError.notFound }
        return url
    }

    private func makeRequest(url: URL, token: GitProviderToken) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeJSONRequest(url: URL, token: GitProviderToken, method: String, body: [String: String]) throws -> URLRequest {
        var request = makeRequest(url: url, token: token)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func send(_ request: URLRequest, write: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await httpClient.data(for: request)
        guard !(200..<300).contains(response.statusCode) else { return (data, response) }
        let message = (try? decoder.decode(GitLabIssueErrorResponse.self, from: data))?.text ?? ""
        switch response.statusCode {
        case 401:
            throw HostedIssueError.reauthorizationRequired
        case 403 where write:
            throw HostedIssueError.missingScope("write access to this repository")
        // GitLab answers 403 for a project whose issues feature is turned off or limited to members.
        case 403:
            throw HostedIssueError.trackerDisabled
        case 404:
            throw HostedIssueError.notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                .map { Date(timeIntervalSinceNow: $0) }
                ?? response.value(forHTTPHeaderField: "RateLimit-Reset").flatMap(TimeInterval.init)
                    .map(Date.init(timeIntervalSince1970:))
            throw HostedIssueError.rateLimited(retryAfter: retryAfter)
        default:
            throw HostedIssueError.providerMessage(
                message.isEmpty ? "GitLab issue request failed (HTTP \(response.statusCode))." : message
            )
        }
    }
}

private struct GitLabIssueErrorResponse: Decodable {
    var message: String?
    var error: String?

    var text: String? { message ?? error }

    enum CodingKeys: String, CodingKey { case message, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `message` is a string or an object of field errors.
        message = (try? container.decode(String.self, forKey: .message))
            ?? (try? container.decode([String: [String]].self, forKey: .message))?
                .map { "\($0.key) \($0.value.joined(separator: ", "))" }.sorted().joined(separator: "; ")
        error = try? container.decode(String.self, forKey: .error)
    }
}

private struct GitLabIssueUser: Decodable {
    var id: Int
    var username: String
    var name: String?
    var avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case avatarURL = "avatar_url"
    }

    var person: HostedIssuePerson {
        HostedIssuePerson(id: username, displayName: name ?? username, avatarURL: avatarURL)
    }
}

private struct GitLabIssueResponse: Decodable {
    var iid: Int
    var title: String
    var state: String
    var description: String?
    var webURL: URL?
    var author: GitLabIssueUser?
    var assignees: [GitLabIssueUser]?
    var labels: [String]?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case iid, title, state, description, author, assignees, labels
        case webURL = "web_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var summary: HostedIssueSummary {
        HostedIssueSummary(
            number: iid,
            title: title,
            state: state == "closed" ? .closed : .open,
            stateName: nil,
            workItemType: nil,
            author: author?.person,
            assignees: assignees?.map(\.person) ?? [],
            labels: labels?.map { HostedIssueLabel(name: $0, color: nil) } ?? [],
            createdAt: createdAt,
            updatedAt: updatedAt,
            webURL: webURL
        )
    }
}

private struct GitLabIssueNoteResponse: Decodable {
    var id: Int
    var body: String
    var system: Bool
    var author: GitLabIssueUser?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, body, system, author
        case createdAt = "created_at"
    }

    var comment: HostedIssueComment {
        HostedIssueComment(id: String(id), author: author?.person, body: body, format: .markdown, createdAt: createdAt)
    }
}
