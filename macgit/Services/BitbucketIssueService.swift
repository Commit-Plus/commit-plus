// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Bitbucket Cloud repository issues through the 2.0 REST API.
struct BitbucketIssueService: HostedIssueProviding {
    static let pageSize = 30
    static let openStates = ["new", "open", "on hold"]
    static let closedStates = ["resolved", "invalid", "duplicate", "wontfix", "closed"]
    static let missingEmailMessage = "Add your Atlassian account email to the Bitbucket account in Settings → Accounts to use Bitbucket Issues."

    private let httpClient: GitProviderHTTPClient
    private let apiBaseURL: URL
    private let decoder = JSONDecoder.hostedIssueDecoder()

    init(
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        apiBaseURL: URL = GitProviderHost.bitbucketDotOrg.apiURL
    ) {
        self.httpClient = httpClient
        self.apiBaseURL = apiBaseURL
    }

    func listIssues(
        repository: GitRepositoryIdentity,
        account: GitProviderAccount,
        token: GitProviderToken,
        filter: HostedIssueFilter,
        search: String,
        cursor: HostedIssueCursor?
    ) async throws -> HostedIssuePage {
        let url: URL
        if case .url(let next) = cursor {
            url = next
        } else {
            var clauses: [String] = []
            switch filter.state {
            case .open: clauses.append(Self.stateClause(Self.openStates))
            case .closed: clauses.append(Self.stateClause(Self.closedStates))
            case .all: break
            }
            if filter.relationship != .all {
                let uuid = try await currentUserUUID(token: token)
                let field = filter.relationship == .assignedToMe ? "assignee" : "reporter"
                clauses.append("\(field).uuid=\(Self.quoted(uuid))")
            }
            let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                if let id = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))) {
                    clauses.append("id=\(id)")
                } else {
                    clauses.append("title~\(Self.quoted(text))")
                }
            }
            var query = [
                URLQueryItem(name: "sort", value: "-updated_on"),
                URLQueryItem(name: "pagelen", value: String(Self.pageSize)),
            ]
            if !clauses.isEmpty {
                query.append(URLQueryItem(name: "q", value: clauses.joined(separator: " AND ")))
            }
            url = try issuesURL(repository, query: query)
        }
        let (data, _) = try await send(makeRequest(url: url, token: token))
        let page = try decoder.decode(BitbucketPage<BitbucketIssueResponse>.self, from: data)
        return HostedIssuePage(items: page.values.map(\.summary), next: page.next.map(HostedIssueCursor.url))
    }

    func issueDetail(
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> HostedIssueDetail {
        let (data, _) = try await send(makeRequest(url: issuesURL(repository, path: [String(number)]), token: token))
        let issue = try decoder.decode(BitbucketIssueResponse.self, from: data)

        var comments: [HostedIssueComment] = []
        var commentsUnavailable = false
        do {
            var next: URL? = try issuesURL(repository, path: [String(number), "comments"],
                                           query: [URLQueryItem(name: "pagelen", value: "100")])
            var pages = 0
            while let url = next, pages < 10 {
                let (data, _) = try await send(makeRequest(url: url, token: token))
                let page = try decoder.decode(BitbucketPage<BitbucketCommentResponse>.self, from: data)
                // Entries without text record field changes, not comments.
                comments += page.values.compactMap(\.comment)
                next = page.next
                pages += 1
            }
        } catch let error as HostedIssueError where error == .reauthorizationRequired {
            throw error
        } catch {
            commentsUnavailable = true
        }
        return HostedIssueDetail(
            summary: issue.summary,
            body: issue.content?.raw ?? "",
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
        let request = try makeJSONRequest(url: issuesURL(repository), token: token, method: "POST", body: [
            "title": draft.title,
            "content": ["raw": draft.body],
        ])
        let (data, _) = try await send(request, write: true)
        return try decoder.decode(BitbucketIssueResponse.self, from: data).summary
    }

    func addComment(
        _ body: String,
        number: Int,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        let request = try makeJSONRequest(
            url: issuesURL(repository, path: [String(number), "comments"]),
            token: token,
            method: "POST",
            body: ["content": ["raw": body]]
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
            url: issuesURL(repository, path: [String(number)]),
            token: token,
            method: "PUT",
            body: ["state": state == .closed ? "resolved" : "open"]
        )
        _ = try await send(request, write: true)
    }

    // MARK: - Requests

    private func currentUserUUID(token: GitProviderToken) async throws -> String {
        let (data, _) = try await send(makeRequest(url: apiBaseURL.appendingPathComponent("user"), token: token))
        return try decoder.decode(BitbucketUser.self, from: data).uuid ?? ""
    }

    private static func stateClause(_ states: [String]) -> String {
        "(" + states.map { "state=\(quoted($0))" }.joined(separator: " OR ") + ")"
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func issuesURL(_ repository: GitRepositoryIdentity, path: [String] = [], query: [URLQueryItem] = []) throws -> URL {
        var url = apiBaseURL
            .appendingPathComponent("repositories")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("issues")
        for component in path { url.appendPathComponent(component) }
        guard !query.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let result = components?.url else { throw HostedIssueError.notFound }
        return result
    }

    private func makeRequest(url: URL, token: GitProviderToken) throws -> URLRequest {
        guard let email = token.apiUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            throw HostedIssueError.accountUpdateRequired(Self.missingEmailMessage)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Basic " + Data("\(email):\(token.accessToken)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeJSONRequest(url: URL, token: GitProviderToken, method: String, body: [String: Any]) throws -> URLRequest {
        var request = try makeRequest(url: url, token: token)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private func send(_ request: URLRequest, write: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await httpClient.data(for: request)
        guard !(200..<300).contains(response.statusCode) else { return (data, response) }
        let message = (try? decoder.decode(BitbucketErrorResponse.self, from: data))?.error.message ?? ""
        switch response.statusCode {
        case 401:
            throw HostedIssueError.reauthorizationRequired
        case 403:
            throw HostedIssueError.missingScope(write
                ? "an API token with the write:issue:bitbucket scope"
                : "an API token with the read:issue:bitbucket scope")
        case 404 where message.localizedCaseInsensitiveContains("issue tracker"):
            throw HostedIssueError.trackerDisabled
        case 404:
            throw HostedIssueError.notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw HostedIssueError.rateLimited(retryAfter: retryAfter.map { Date(timeIntervalSinceNow: $0) })
        default:
            throw HostedIssueError.providerMessage(
                message.isEmpty ? "Bitbucket issue request failed (HTTP \(response.statusCode))." : message
            )
        }
    }
}

private struct BitbucketPage<Value: Decodable>: Decodable {
    var values: [Value]
    var next: URL?
}

private struct BitbucketErrorResponse: Decodable {
    struct Detail: Decodable { var message: String }
    var error: Detail
}

private struct BitbucketUser: Decodable {
    struct Links: Decodable {
        struct Link: Decodable { var href: URL? }
        var avatar: Link?
    }

    var uuid: String?
    var displayName: String?
    var nickname: String?
    var links: Links?

    enum CodingKeys: String, CodingKey {
        case uuid, nickname, links
        case displayName = "display_name"
    }

    var person: HostedIssuePerson {
        HostedIssuePerson(id: uuid ?? nickname ?? "", displayName: displayName ?? nickname ?? "", avatarURL: links?.avatar?.href)
    }
}

private struct BitbucketContent: Decodable {
    var raw: String?
}

private struct BitbucketIssueResponse: Decodable {
    struct Links: Decodable {
        struct Link: Decodable { var href: URL? }
        var html: Link?
    }

    var id: Int
    var title: String
    var state: String
    var kind: String?
    var priority: String?
    var content: BitbucketContent?
    var reporter: BitbucketUser?
    var assignee: BitbucketUser?
    var createdOn: Date?
    var updatedOn: Date?
    var links: Links?

    enum CodingKeys: String, CodingKey {
        case id, title, state, kind, priority, content, reporter, assignee, links
        case createdOn = "created_on"
        case updatedOn = "updated_on"
    }

    var summary: HostedIssueSummary {
        let closed = BitbucketIssueService.closedStates.contains(state)
        return HostedIssueSummary(
            number: id,
            title: title,
            state: closed ? .closed : .open,
            stateName: state.prefix(1).uppercased() + state.dropFirst(),
            workItemType: nil,
            author: reporter?.person,
            assignees: assignee.map { [$0.person] } ?? [],
            labels: [kind, priority].compactMap { $0 }.map { HostedIssueLabel(name: $0, color: nil) },
            createdAt: createdOn,
            updatedAt: updatedOn,
            webURL: links?.html?.href
        )
    }
}

private struct BitbucketCommentResponse: Decodable {
    var id: Int
    var content: BitbucketContent?
    var user: BitbucketUser?
    var createdOn: Date?

    enum CodingKeys: String, CodingKey {
        case id, content, user
        case createdOn = "created_on"
    }

    var comment: HostedIssueComment? {
        guard let raw = content?.raw, !raw.isEmpty else { return nil }
        return HostedIssueComment(id: String(id), author: user?.person, body: raw, format: .markdown, createdAt: createdOn)
    }
}
