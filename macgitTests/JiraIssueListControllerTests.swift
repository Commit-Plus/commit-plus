// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

@MainActor
final class JiraIssueListControllerTests: XCTestCase {
    private var client: StubJiraIssueService!
    private var connectionController: JiraConnectionController!
    private var filters: InMemoryJiraIssueFilterStore!
    private let repositoryA = URL(fileURLWithPath: "/tmp/repo-a")
    private let repositoryB = URL(fileURLWithPath: "/tmp/repo-b")

    override func setUp() async throws {
        client = StubJiraIssueService()
        client.validateResults = [.success(JiraValidatedAccount(accountID: "acc-1", displayName: "Dev", email: "dev@example.com", apiBase: .site))]
        connectionController = JiraConnectionController(
            client: client,
            tokenStore: InMemoryJiraTokenStore(),
            connectionStore: InMemoryJiraConnectionStore()
        )
        await connectionController.updateMacgitAccount(uid: "uid-a")
        let connected = await connectionController.connect(site: "acme", email: "dev@example.com", token: "t")
        XCTAssertTrue(connected)
        filters = InMemoryJiraIssueFilterStore()
    }

    private func makeController(repository: URL? = nil) -> JiraIssueListController {
        JiraIssueListController(
            repositoryURL: repository ?? repositoryA,
            connectionController: connectionController,
            filterStore: filters,
            searchDebounce: .zero
        )
    }

    func testDefaultLoadUsesDefaultJQL() async throws {
        client.searchHandler = { _, _ in JiraIssuePage(issues: [.stub("PROJ-1")], nextPageToken: nil) }
        let controller = makeController()

        await controller.activate()
        try await waitForIdle(controller)

        XCTAssertEqual(controller.items.map(\.key), ["PROJ-1"])
        XCTAssertEqual(client.searchedJQL.first, JiraJQLBuilder.jql(for: .default, supportsSprints: true))
        XCTAssertEqual(controller.projectOptions.map(\.key), ["PROJ"])
        XCTAssertEqual(controller.sprintOptions.map(\.name), ["Sprint 7"])
    }

    func testStaleResponseIsDropped() async throws {
        client.searchHandler = { jql, _ in
            if jql.contains("openSprints") {
                // Ignores cancellation so a late result really arrives after the newer one.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { continuation.resume() }
                }
                return JiraIssuePage(issues: [.stub("OLD-1")], nextPageToken: nil)
            }
            return JiraIssuePage(issues: [.stub("NEW-1")], nextPageToken: nil)
        }
        let controller = makeController()

        await controller.activate()
        controller.updateFilter { $0.sprintScope = .backlog }
        try await waitForIdle(controller)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(controller.items.map(\.key), ["NEW-1"])
    }

    func testFilterIsRestoredPerRepositoryAndSearchTextIsNotPersisted() async throws {
        let controller = makeController()
        await controller.activate()
        try await waitForIdle(controller)

        controller.searchText = "login"
        controller.updateFilter { $0.projectKeys = ["PROJ"] }
        try await waitForIdle(controller)
        try await Task.sleep(for: .milliseconds(50))

        let stored = try XCTUnwrap(filters.filters[repositoryA.standardizedFileURL.path])
        XCTAssertEqual(stored.projectKeys, ["PROJ"])
        XCTAssertEqual(stored.searchText, "")

        let reopened = makeController()
        await reopened.activate()
        XCTAssertEqual(reopened.filter.projectKeys, ["PROJ"])
        XCTAssertEqual(reopened.searchText, "")

        let other = makeController(repository: repositoryB)
        await other.activate()
        XCTAssertEqual(other.filter, .default)
    }

    func testResetFiltersRestoresDefaultAndClearsStoredFilter() async throws {
        let controller = makeController()
        await controller.activate()
        controller.updateFilter { $0.sprintScope = .any }
        try await waitForIdle(controller)

        controller.resetFilters()
        try await waitForIdle(controller)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(controller.filter, .default)
        XCTAssertNil(filters.filters[repositoryA.standardizedFileURL.path])
    }

    func testUnauthorizedMarksConnectionForReconnect() async throws {
        client.searchHandler = { _, _ in throw JiraError.needsReconnect }
        let controller = makeController()

        await controller.activate()
        try await waitForIdle(controller)

        XCTAssertEqual(controller.error, .needsReconnect)
        XCTAssertEqual(connectionController.connection?.needsReconnect, true)
    }

    func testEmptyStateDistinguishesNoMatchFromNoIssues() async throws {
        client.searchHandler = { jql, _ in
            jql.contains("openSprints")
                ? JiraIssuePage(issues: [], nextPageToken: nil)
                : JiraIssuePage(issues: [.stub("PROJ-9")], nextPageToken: nil)
        }
        let controller = makeController()
        await controller.activate()
        try await waitForIdle(controller)
        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertTrue(controller.hasAnyAssignedIssues)

        client.searchHandler = { _, _ in JiraIssuePage(issues: [], nextPageToken: nil) }
        controller.refresh()
        try await waitForIdle(controller)
        XCTAssertFalse(controller.hasAnyAssignedIssues)
    }

    func testRowsStayVisibleWhenRefreshFails() async throws {
        client.searchHandler = { _, _ in JiraIssuePage(issues: [.stub("PROJ-1")], nextPageToken: nil) }
        let controller = makeController()
        await controller.activate()
        try await waitForIdle(controller)

        client.searchHandler = { _, _ in throw JiraError.unreachable }
        controller.refresh()
        try await waitForIdle(controller)

        XCTAssertEqual(controller.error, .unreachable)
        XCTAssertEqual(controller.items.map(\.key), ["PROJ-1"])
    }

    func testLoadMoreAppendsNextPage() async throws {
        client.searchHandler = { _, token in
            token == nil
                ? JiraIssuePage(issues: [.stub("PROJ-1")], nextPageToken: "p2")
                : JiraIssuePage(issues: [.stub("PROJ-2")], nextPageToken: nil)
        }
        let controller = makeController()
        await controller.activate()
        try await waitForIdle(controller)

        controller.loadMore()
        try await waitForIdle(controller)

        XCTAssertEqual(controller.items.map(\.key), ["PROJ-1", "PROJ-2"])
        XCTAssertNil(controller.nextPageToken)
    }

    func testUnknownProjectKeySearchFallsBackToTextSearch() async throws {
        client.searchHandler = { jql, _ in
            if jql.contains("key = ") { throw JiraError.invalidQuery }
            return JiraIssuePage(issues: [], nextPageToken: nil)
        }
        let controller = makeController()
        await controller.activate()
        try await waitForIdle(controller)

        controller.searchText = "NOPE-1"
        try await Task.sleep(for: .milliseconds(50))
        try await waitForIdle(controller)

        XCTAssertNil(controller.error)
        XCTAssertTrue(client.searchedJQL.contains { $0.contains("summary ~ \"NOPE 1\"") && !$0.contains("key = ") })
    }

    func testRemovingConnectionClearsList() async throws {
        client.searchHandler = { _, _ in JiraIssuePage(issues: [.stub("PROJ-1")], nextPageToken: nil) }
        let controller = makeController()
        await controller.activate()
        try await waitForIdle(controller)

        await connectionController.remove()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertNil(controller.connection)
    }

    private func waitForIdle(_ controller: JiraIssueListController, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            try await Task.sleep(for: .milliseconds(10))
        } while (controller.isLoading || controller.isLoadingMore) && Date() < deadline
        XCTAssertFalse(controller.isLoading || controller.isLoadingMore, "Timed out waiting for Jira load")
    }
}

final class InMemoryJiraIssueFilterStore: JiraIssueFilterStoring {
    var filters: [String: JiraIssueFilter] = [:]

    func filter(forRepositoryKey key: String) async -> JiraIssueFilter? { filters[key] }

    func save(_ filter: JiraIssueFilter, forRepositoryKey key: String) async {
        // Round-trip through Codable so tests see exactly what is persisted.
        let data = try! JSONEncoder().encode(filter)
        filters[key] = filter.isDefault ? nil : try! JSONDecoder().decode(JiraIssueFilter.self, from: data)
    }
}

extension JiraIssue {
    static func stub(_ key: String) -> JiraIssue {
        JiraIssue(
            id: key,
            key: key,
            summary: "Summary \(key)",
            statusName: "To Do",
            statusCategory: .toDo,
            issueTypeName: "Task",
            priorityName: "Medium",
            projectKey: String(key.split(separator: "-").first ?? ""),
            projectName: "Project",
            updated: nil,
            sprints: [JiraSprintRef(id: 7, name: "Sprint 7", state: "active")]
        )
    }
}
