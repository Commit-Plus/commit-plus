// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class GitHubNotificationTests: XCTestCase {
    func testFetchRequestsLatestFiftyIncludingReadAndKeepsConditionalHeader() async throws {
        let client = NotificationHTTPStub(status: 304, headers: ["X-Poll-Interval": "120"])
        let result = try await GitHubNotificationService(httpClient: client).fetch(account: account(), token: token(), lastModified: "exact-header")
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.host, "api.github.com")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "per_page" }?.value, "50")
        XCTAssertEqual(query?.first { $0.name == "all" }?.value, "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "exact-header")
        XCTAssertNil(result.notifications)
        XCTAssertEqual(result.pollInterval, 120)
    }

    func testRateLimitRetainsServerRetryTime() async throws {
        let client = NotificationHTTPStub(status: 429, headers: ["Retry-After": "180"])
        do {
            _ = try await GitHubNotificationService(httpClient: client).fetch(account: account(), token: token(), lastModified: nil)
            XCTFail("Expected rate limit")
        } catch let error as GitHubNotificationError {
            XCTAssertGreaterThan(error.retryAt.timeIntervalSinceNow, 175)
        }
    }

    func testDoneUsesAccountHostAndNeverSubjectURL() async throws {
        var enterprise = account()
        enterprise.hostURL = URL(string: "https://git.example.com")!
        let client = NotificationHTTPStub(status: 204)
        try await GitHubNotificationService(httpClient: client).update(threadID: "123", done: true, account: enterprise, token: token())
        XCTAssertEqual(client.requests.first?.url?.absoluteString, "https://git.example.com/api/v3/notifications/threads/123")
        XCTAssertEqual(client.requests.first?.httpMethod, "DELETE")
    }

    func testCacheCapsDeduplicatesAndSurvivesSQLiteReopen() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        var cache = GitHubNotificationCache()
        let values = (0..<80).map { notification(String($0), updated: Double($0)) }
        cache.replace(with: values + values)
        XCTAssertEqual(cache.notifications.count, 50)
        XCTAssertEqual(cache.notifications.first?.id, "79")
        XCTAssertEqual(cache.notifications.last?.id, "30")
        let id = GitHubNotificationCache.key(for: account())
        try await fixture.store.transaction { transaction in
            try transaction.set(cache, in: "githubNotificationCache", id: id)
        }
        let reopened = try await fixture.reopen()
        let persisted = try await reopened.readValue(GitHubNotificationCache.self, in: "githubNotificationCache", id: id)
        XCTAssertEqual(persisted?.notifications, cache.notifications)
        var another = account(); another.providerUserID = "other"
        let absent = try await reopened.readValue(GitHubNotificationCache.self, in: "githubNotificationCache", id: GitHubNotificationCache.key(for: another))
        XCTAssertNil(absent)
        another = account(); another.hostURL = URL(string: "https://git.example.com")!
        XCTAssertNotEqual(GitHubNotificationCache.key(for: another), id)
    }

    func testFreshCacheAvoidsFetchButReadActionIsNotBlockedByPollInterval() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let account = account()
        let id = GitHubNotificationCache.key(for: account)
        var cache = GitHubNotificationCache()
        cache.replace(with: [notification("123", updated: 0)])
        cache.refreshedAt = .now
        cache.nextFetchAt = .now.addingTimeInterval(120)
        try await fixture.store.transaction { try $0.set(cache, in: "githubNotificationCache", id: id) }
        let service = NotificationServiceStub()
        let controller = GitHubNotificationController(tokenVault: NotificationTokenStub(), dataStore: fixture.store, service: service, defaults: fixture.defaults)
        controller.acceptAccounts([account])
        for _ in 0..<100 where controller.caches[id] == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(controller.unreadCount, 1)
        controller.opened()
        controller.refreshSelected()
        XCTAssertEqual(service.fetches, 0)
        controller.update(cache.notifications[0], account: account, done: false)
        for _ in 0..<100 where controller.busyAccounts.contains(id) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(service.updates, 1)
        XCTAssertEqual(controller.unreadCount, 0)
        controller.acceptAccounts([])
        for _ in 0..<100 {
            let stored = try await fixture.store.readValue(GitHubNotificationCache.self, in: "githubNotificationCache", id: id)
            if stored == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let removed = try await fixture.store.readValue(GitHubNotificationCache.self, in: "githubNotificationCache", id: id)
        XCTAssertNil(removed)
        XCTAssertEqual(controller.unreadCount, 0)
    }

    func testViewMarksCacheReadAndSyncsOnlyOnce() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let account = account()
        let id = GitHubNotificationCache.key(for: account)
        let item = notification("123", updated: 0)
        var cache = GitHubNotificationCache()
        cache.replace(with: [item])
        cache.refreshedAt = .now
        cache.nextFetchAt = .now.addingTimeInterval(120)
        try await fixture.store.transaction { try $0.set(cache, in: "githubNotificationCache", id: id) }
        let service = NotificationServiceStub()
        var openedURLs: [URL] = []
        let controller = GitHubNotificationController(tokenVault: NotificationTokenStub(), dataStore: fixture.store,
            service: service, defaults: fixture.defaults, openURL: { openedURLs.append($0); return true })
        controller.acceptAccounts([account])
        for _ in 0..<100 where controller.caches[id] == nil { try await Task.sleep(for: .milliseconds(10)) }
        controller.open(item, account: account)
        XCTAssertEqual(controller.unreadCount, 0)
        controller.open(item, account: account)
        for _ in 0..<100 {
            if service.updates == 1 && !controller.busyAccounts.contains(id) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(service.updates, 1)
        XCTAssertEqual(openedURLs.count, 2)
        XCTAssertEqual(openedURLs.first?.absoluteString, "https://github.com/org/repo/pull/42")
        let persisted = try await fixture.store.readValue(GitHubNotificationCache.self, in: "githubNotificationCache", id: id)
        XCTAssertEqual(persisted?.notifications.first?.unread, false)
        XCTAssertTrue(persisted?.pendingReads?.isEmpty ?? true)
    }

    private func account() -> GitProviderAccount {
        GitProviderAccount(id: "a", macgitUID: "local", provider: .github, hostURL: URL(string: "https://github.com")!, providerUserID: "1", username: "octocat", displayName: nil, avatarURL: nil, scopes: ["repo"], permissions: [:], tokenStatus: .valid, connectedAt: .now, lastValidatedAt: nil)
    }
    private func token() -> GitProviderToken { GitProviderToken(accessToken: "test-token", refreshToken: nil, expiresAt: nil, tokenType: "bearer") }
    private func notification(_ id: String, updated: Double) -> GitHubNotification {
        GitHubNotification(id: id, subject: .init(title: "Review", url: URL(string: "https://api.github.com/repos/org/repo/pulls/42"), type: "PullRequest"), repository: .init(fullName: "org/repo", htmlURL: URL(string: "https://github.com/org/repo")!), reason: "review_requested", unread: true, updatedAt: Date(timeIntervalSince1970: updated))
    }
}

private final class NotificationHTTPStub: GitProviderHTTPClient {
    var status: Int
    var headers: [String: String]
    var requests: [URLRequest] = []
    init(status: Int, headers: [String: String] = [:]) { self.status = status; self.headers = headers }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

private final class NotificationServiceStub: GitHubNotificationProviding {
    var fetches = 0
    var updates = 0
    func fetch(account: GitProviderAccount, token: GitProviderToken, lastModified: String?) async throws -> GitHubNotificationFetch {
        fetches += 1
        return .init(notifications: nil, lastModified: lastModified, pollInterval: 60)
    }
    func update(threadID: String, done: Bool, account: GitProviderAccount, token: GitProviderToken) async throws { updates += 1 }
}

private final class NotificationTokenStub: GitProviderTokenVault {
    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? { .init(accessToken: "test-token", refreshToken: nil, expiresAt: nil, tokenType: "bearer") }
    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {}
    func deleteToken(for account: GitProviderAccount) throws {}
}
