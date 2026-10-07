// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

protocol GitHubNotificationProviding {
    func fetch(account: GitProviderAccount, token: GitProviderToken, lastModified: String?) async throws -> GitHubNotificationFetch
    func update(threadID: String, done: Bool, account: GitProviderAccount, token: GitProviderToken) async throws
}

struct GitHubNotificationService: GitHubNotificationProviding {
    var httpClient: any GitProviderHTTPClient = URLSessionGitProviderHTTPClient()

    func fetch(account: GitProviderAccount, token: GitProviderToken, lastModified: String?) async throws -> GitHubNotificationFetch {
        var components = URLComponents(url: apiURL(account).appending(path: "notifications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "all", value: "true"), URLQueryItem(name: "per_page", value: "50")]
        var request = request(url: components.url!, token: token)
        request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        let (data, response) = try await httpClient.data(for: request)
        try validate(response)
        let interval = max(60, Double(response.value(forHTTPHeaderField: "X-Poll-Interval") ?? "") ?? 60)
        if response.statusCode == 304 {
            return GitHubNotificationFetch(notifications: nil, lastModified: lastModified, pollInterval: interval)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return GitHubNotificationFetch(
            notifications: try decoder.decode([GitHubNotification].self, from: data),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified"), pollInterval: interval
        )
    }

    func update(threadID: String, done: Bool, account: GitProviderAccount, token: GitProviderToken) async throws {
        guard !threadID.isEmpty, threadID.allSatisfy(\.isNumber) else { throw GitProviderAuthError.invalidResponse }
        var request = request(url: apiURL(account).appending(path: "notifications/threads/\(threadID)"), token: token)
        request.httpMethod = done ? "DELETE" : "PATCH"
        let (_, response) = try await httpClient.data(for: request)
        try validate(response)
    }

    private func apiURL(_ account: GitProviderAccount) -> URL {
        GitProviderHost(kind: .github, baseURL: account.hostURL).apiURL
    }

    private func request(url: URL, token: GitProviderToken) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func validate(_ response: HTTPURLResponse) throws {
        if response.statusCode == 304 || (200..<300).contains(response.statusCode) { return }
        if response.statusCode == 401 {
            throw GitHubNotificationError(message: "Reconnect this GitHub account: its API token is expired or revoked.", retryAt: Date.now.addingTimeInterval(300))
        }
        let retry = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "").map { Date.now.addingTimeInterval($0) }
        let reset = Double(response.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "").map { Date(timeIntervalSince1970: $0) }
        if response.statusCode == 429 || retry != nil || response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
            throw GitHubNotificationError(message: "GitHub rate limit reached. Refresh will resume after the server's backoff.", retryAt: max(retry ?? .distantPast, reset ?? Date.now.addingTimeInterval(60)))
        }
        if response.statusCode == 403 {
            throw GitHubNotificationError(message: "This account cannot access GitHub notifications. Check token type, notifications/repo permissions, and organization access. GitHub App and fine-grained tokens are unsupported.", retryAt: Date.now.addingTimeInterval(300))
        }
        throw GitHubNotificationError(message: "GitHub notifications request failed (HTTP \(response.statusCode)).", retryAt: Date.now.addingTimeInterval(60))
    }
}
