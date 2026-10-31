// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

@MainActor
final class HostedIssueControllerTests: XCTestCase {
    private let repositoryURL = URL(fileURLWithPath: "/tmp/hosted-issue-repo")
    private let githubAccount = HostedIssueFixtures.account(.github, host: "https://github.com")
    private var remotes: [String: String] = [:]
    private var remoteOrder: [String] = []
    private var accounts: [GitProviderAccount] = []
    private var vault = HostedIssueTokenVault()
    private var preferences = MemoryHostedIssuePreferences()
    private var provider = FakeHostedIssueProvider()
    private var center = NotificationCenter()
    private var clock = Date(timeIntervalSince1970: 1_000)

    override func setUp() {
        super.setUp()
        remotes = ["origin": "https://github.com/me/app.git", "upstream": "https://github.com/org/app.git"]
        remoteOrder = ["upstream", "origin"]
        accounts = [githubAccount]
        vault = HostedIssueTokenVault()
        vault.tokens[githubAccount.id] = HostedIssueFixtures.token
        preferences = MemoryHostedIssuePreferences()
        provider = FakeHostedIssueProvider()
        center = NotificationCenter()
    }

    private func makeController() -> HostedIssueController {
        HostedIssueController(
            repositoryURL: repositoryURL,
            credentialResolver: GitProviderAPICredentialResolver(accounts: { [unowned self] in accounts }, tokenVault: vault),
            services: [.github: provider, .gitlab: provider],
            preferenceStore: preferences,
            remoteNamesProvider: { [unowned self] _ in remoteOrder },
            remoteURLProvider: { [unowned self] _, name in remotes[name] },
            searchDebounce: .milliseconds(1),
            notificationCenter: center,
            now: { [unowned self] in clock }
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Timed out", file: file, line: line)
    }

    func testDefaultsToOriginAndOpenFilter() async {
        provider.pages = [HostedIssuePage(items: [.fixture(1), .fixture(2)], next: .page(2))]
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }

        XCTAssertEqual(controller.remotes.map(\.name), ["origin", "upstream"])
        XCTAssertEqual(controller.selectedRemote?.name, "origin")
        XCTAssertEqual(controller.provider, .github)
        XCTAssertEqual(controller.items.map(\.number), [1, 2])
        XCTAssertEqual(controller.next, .page(2))
        XCTAssertEqual(provider.listCalls.first?.filter, .default)
        XCTAssertEqual(provider.listCalls.first?.repository.owner, "me")
    }

    func testReturningAfterAMinuteRefreshes() async {
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }
        controller.deactivate()

        clock.addTimeInterval(30)
        await controller.activate()
        XCTAssertEqual(provider.listCalls.count, 1)

        controller.deactivate()
        clock.addTimeInterval(31)
        await controller.activate()
        await waitUntil { self.provider.listCalls.count == 2 }
    }

    func testRememberedRemoteAndFilterAreRestored() async {
        preferences.remote = "upstream"
        preferences.filters["upstream"] = HostedIssueFilter(state: .closed, relationship: .assignedToMe)
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }

        XCTAssertEqual(controller.selectedRemote?.name, "upstream")
        XCTAssertEqual(controller.filter, HostedIssueFilter(state: .closed, relationship: .assignedToMe))
        XCTAssertEqual(provider.listCalls.last?.repository.owner, "org")
    }

    func testSelectingRemoteSavesChoice() async {
        let controller = makeController()
        await controller.activate()
        controller.selectRemote(named: "upstream")
        await waitUntil { controller.selectedRemote?.name == "upstream" }

        XCTAssertEqual(preferences.remote, "upstream")
    }

    func testFilterChangeIsSavedPerRemote() async {
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }
        controller.updateFilter { $0.relationship = .createdByMe }
        await waitUntil { self.preferences.filters["origin"]?.relationship == .createdByMe }
        await waitUntil { self.provider.listCalls.last?.filter.relationship == .createdByMe }
    }

    func testNoAccountMakesNoRequest() async {
        accounts = []
        let controller = makeController()
        await controller.activate()

        XCTAssertEqual(controller.accountProblem, .noAccount(GitProviderHost(kind: .github, baseURL: URL(string: "https://github.com")!).normalized))
        XCTAssertTrue(provider.listCalls.isEmpty)
    }

    func testMissingTokenAsksToReconnect() async {
        vault.tokens = [:]
        let controller = makeController()
        await controller.activate()

        guard case .reconnect = controller.accountProblem else { return XCTFail("Expected reconnect") }
        XCTAssertTrue(provider.listCalls.isEmpty)
    }

    func testStaleResponseIsDropped() async {
        provider.delays = [.milliseconds(150), .zero]
        provider.pages = [HostedIssuePage(items: [.fixture(1)], next: nil), HostedIssuePage(items: [.fixture(9)], next: nil)]
        let controller = makeController()
        await controller.activate()
        controller.updateFilter { $0.state = .closed }
        await waitUntil { controller.items.map(\.number) == [9] }
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(controller.items.map(\.number), [9])
    }

    func testListErrorIsShown() async {
        provider.listError = HostedIssueError.trackerDisabled
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.error != nil }

        XCTAssertEqual(controller.error, .trackerDisabled)
    }

    func testReselectingIssueUsesCachedDetailUntilRefresh() async {
        provider.pages = [HostedIssuePage(items: [.fixture(1), .fixture(2)], next: nil)]
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }

        controller.select(1)
        await waitUntil { controller.detail?.summary.number == 1 }
        controller.select(2)
        await waitUntil { controller.detail?.summary.number == 2 }
        controller.select(1)

        XCTAssertEqual(controller.detail?.summary.number, 1)
        XCTAssertEqual(provider.detailCalls, [1, 2])

        clock.addTimeInterval(HostedIssueController.detailCacheTTL + 1)
        controller.select(2)
        await waitUntil { self.provider.detailCalls == [1, 2, 2] }

        controller.refresh()
        await waitUntil { self.provider.detailCalls == [1, 2, 2, 2] }
    }

    func testFailedCommentKeepsStateAndIsNotRetried() async {
        provider.pages = [HostedIssuePage(items: [.fixture(1)], next: nil)]
        provider.writeError = HostedIssueError.providerMessage("offline")
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }
        controller.select(1)

        let posted = await controller.addComment("Fixed in main")

        XCTAssertFalse(posted)
        XCTAssertEqual(controller.writeError, .providerMessage("offline"))
        XCTAssertEqual(provider.comments.count, 1)
    }

    func testClosedIssueStaysVisibleUnderOpenFilter() async {
        provider.pages = [
            HostedIssuePage(items: [.fixture(1), .fixture(2)], next: nil),
            HostedIssuePage(items: [.fixture(2)], next: nil),
        ]
        var closed = HostedIssueSummary.fixture(1)
        closed.state = .closed
        provider.details[1] = HostedIssueDetail(summary: closed, body: "", bodyFormat: .markdown, comments: [])
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }
        controller.select(1)

        await controller.setState(.closed)
        await waitUntil { self.provider.listCalls.count == 2 && !controller.isLoading }

        XCTAssertEqual(provider.states.first?.state, .closed)
        XCTAssertEqual(controller.items.map(\.number), [1, 2])
        XCTAssertEqual(controller.items.first?.state, .closed)
        XCTAssertEqual(controller.selectedIssueNumber, 1)
    }

    func testCreatedIssueIsSelected() async {
        provider.created = .fixture(77)
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }

        let created = await controller.createIssue(HostedIssueDraft(title: "  Crash  ", body: ""))

        XCTAssertTrue(created)
        XCTAssertEqual(provider.drafts.first?.title, "Crash")
        XCTAssertEqual(controller.selectedIssueNumber, 77)
        await waitUntil { controller.items.contains { $0.number == 77 } }
    }

    func testSecondWriteDuringAccessCheckIsIgnored() async {
        let controller = makeController()
        await controller.activate()
        await waitUntil { controller.hasLoadedList }
        controller.authorizeWrite = {
            try? await Task.sleep(for: .milliseconds(50))
            return true
        }

        async let first = controller.createIssue(HostedIssueDraft(title: "Crash", body: ""))
        async let second = controller.createIssue(HostedIssueDraft(title: "Crash", body: ""))
        let results = await [first, second]

        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(provider.drafts.count, 1)
    }

    func testBlankTitleAndDeniedAccessSendNothing() async {
        let controller = makeController()
        await controller.activate()
        let blank = await controller.createIssue(HostedIssueDraft(title: "   ", body: ""))
        controller.authorizeWrite = { false }
        let denied = await controller.createIssue(HostedIssueDraft(title: "Crash", body: ""))

        XCTAssertFalse(blank)
        XCTAssertFalse(denied)
        XCTAssertTrue(provider.drafts.isEmpty)
    }

    func testNotificationsForOtherRepositoriesAreIgnored() async {
        let controller = makeController()
        await controller.activate()
        remotes["origin"] = "https://gitlab.com/me/app.git"

        center.post(name: .repositoryRemoteRefsDidRefresh, object: nil, userInfo: ["repositoryURL": URL(fileURLWithPath: "/tmp/other")])
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controller.provider, .github)

        center.post(name: .repositoryRemoteRefsDidRefresh, object: nil, userInfo: ["repositoryURL": repositoryURL])
        await waitUntil { controller.provider == .gitlab }
    }

    func testAddedRemotePublishesProvider() async {
        remotes = [:]
        remoteOrder = []
        let controller = makeController()
        await controller.discoverRemotes()
        XCTAssertNil(controller.provider)

        remotes = ["origin": "git@gitlab.com:me/app.git"]
        remoteOrder = ["origin"]
        center.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
        await waitUntil { controller.provider == .gitlab }
    }
}

extension HostedIssueSummary {
    static func fixture(_ number: Int, state: HostedIssueState = .open) -> HostedIssueSummary {
        HostedIssueSummary(number: number, title: "Issue \(number)", state: state, stateName: nil, workItemType: nil,
                           author: nil, assignees: [], labels: [], createdAt: nil, updatedAt: nil, webURL: nil)
    }
}

final class HostedIssueTokenVault: GitProviderTokenVault {
    var tokens: [String: GitProviderToken] = [:]
    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? { tokens[account.id] }
    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws { tokens[account.id] = token }
    func deleteToken(for account: GitProviderAccount) throws { tokens[account.id] = nil }
}

final class MemoryHostedIssuePreferences: HostedIssuePreferenceStoring, @unchecked Sendable {
    var remote: String?
    var filters: [String: HostedIssueFilter] = [:]
    func remoteName(forRepositoryKey key: String) async -> String? { remote }
    func saveRemoteName(_ name: String, forRepositoryKey key: String) async { remote = name }
    func filter(forRepositoryKey key: String, remote: String) async -> HostedIssueFilter? { filters[remote] }
    func save(_ filter: HostedIssueFilter, forRepositoryKey key: String, remote: String) async { filters[remote] = filter }
}

final class FakeHostedIssueProvider: HostedIssueProviding, @unchecked Sendable {
    struct ListCall {
        var repository: GitRepositoryIdentity
        var filter: HostedIssueFilter
        var search: String
        var cursor: HostedIssueCursor?
    }

    var pages: [HostedIssuePage] = []
    var delays: [Duration] = []
    var listError: Error?
    var writeError: Error?
    var details: [Int: HostedIssueDetail] = [:]
    var created: HostedIssueSummary = .fixture(100)
    private(set) var listCalls: [ListCall] = []
    private(set) var drafts: [HostedIssueDraft] = []
    private(set) var comments: [(body: String, number: Int)] = []
    private(set) var states: [(state: HostedIssueState, number: Int)] = []

    func listIssues(repository: GitRepositoryIdentity, account: GitProviderAccount, token: GitProviderToken,
                    filter: HostedIssueFilter, search: String, cursor: HostedIssueCursor?) async throws -> HostedIssuePage {
        listCalls.append(ListCall(repository: repository, filter: filter, search: search, cursor: cursor))
        let page = pages.isEmpty ? HostedIssuePage(items: [], next: nil) : pages.removeFirst()
        let delay = delays.isEmpty ? .zero : delays.removeFirst()
        // A late response that ignores cancellation, like a request already on the wire.
        if delay > .zero { await Task.detached { try? await Task.sleep(for: delay) }.value }
        if let listError { throw listError }
        return page
    }

    private(set) var detailCalls: [Int] = []

    func issueDetail(number: Int, repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> HostedIssueDetail {
        detailCalls.append(number)
        return details[number] ?? HostedIssueDetail(summary: .fixture(number), body: "", bodyFormat: .markdown, comments: [])
    }

    func createIssue(_ draft: HostedIssueDraft, repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> HostedIssueSummary {
        drafts.append(draft)
        if let writeError { throw writeError }
        return created
    }

    func addComment(_ body: String, number: Int, repository: GitRepositoryIdentity, token: GitProviderToken) async throws {
        comments.append((body, number))
        if let writeError { throw writeError }
    }

    func setState(_ state: HostedIssueState, number: Int, repository: GitRepositoryIdentity, token: GitProviderToken) async throws {
        states.append((state, number))
        if let writeError { throw writeError }
    }
}
