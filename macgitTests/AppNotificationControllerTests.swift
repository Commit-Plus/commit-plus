// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class AppNotificationControllerTests: XCTestCase {
    func testDailyCheckRunsOncePerRepositoryAndPersistsNotification() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let controller = AppNotificationController(dataStore: fixture.store, calendar: calendar)
        let repository = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        let firstDay = Date(timeIntervalSince1970: 1_800_000_000)

        await controller.recordDailyBranchCleanupCheck(
            repositoryURL: repository,
            branchNames: ["feature/one", "feature/two", "feature/one"],
            now: firstDay
        )
        await controller.recordDailyBranchCleanupCheck(
            repositoryURL: repository,
            branchNames: ["feature/three"],
            now: firstDay.addingTimeInterval(60)
        )

        XCTAssertEqual(controller.notifications.count, 1)
        XCTAssertEqual(controller.notifications[0].branchNames, ["feature/one", "feature/two"])

        let reopenedStore = try await fixture.reopen()
        let reopened = AppNotificationController(dataStore: reopenedStore, calendar: calendar)
        await reopened.load()
        XCTAssertEqual(reopened.notifications, controller.notifications)
    }

    func testEmptyDailyCheckPreventsLaterInsertionUntilNextDay() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let controller = AppNotificationController(dataStore: fixture.store, calendar: calendar)
        let repository = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        let firstDay = Date(timeIntervalSince1970: 1_800_000_000)

        await controller.recordDailyBranchCleanupCheck(
            repositoryURL: repository,
            branchNames: [],
            now: firstDay
        )
        await controller.recordDailyBranchCleanupCheck(
            repositoryURL: repository,
            branchNames: ["feature/later"],
            now: firstDay.addingTimeInterval(60)
        )
        XCTAssertTrue(controller.notifications.isEmpty)

        await controller.recordDailyBranchCleanupCheck(
            repositoryURL: repository,
            branchNames: ["feature/tomorrow"],
            now: firstDay.addingTimeInterval(86_400)
        )
        XCTAssertEqual(controller.notifications.map(\.branchNames), [["feature/tomorrow"]])
    }

    func testChecksAreIndependentPerRepository() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let controller = AppNotificationController(dataStore: fixture.store)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await controller.recordDailyBranchCleanupCheck(
            repositoryURL: URL(fileURLWithPath: "/tmp/one", isDirectory: true),
            branchNames: ["feature/one"],
            now: now
        )
        await controller.recordDailyBranchCleanupCheck(
            repositoryURL: URL(fileURLWithPath: "/tmp/two", isDirectory: true),
            branchNames: ["feature/two"],
            now: now
        )

        XCTAssertEqual(controller.notifications.count, 2)
    }

    func testDeleteAllRemovesPersistedNotificationsWithoutResettingDailyChecks() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let controller = AppNotificationController(dataStore: fixture.store, calendar: calendar)
        let repository = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await controller.recordDailyBranchCleanupCheck(
            repositoryURL: repository,
            branchNames: ["feature/one"],
            now: now
        )
        await controller.deleteAll()

        XCTAssertTrue(controller.notifications.isEmpty)

        let reopenedStore = try await fixture.reopen()
        let reopened = AppNotificationController(dataStore: reopenedStore, calendar: calendar)
        await reopened.load()
        XCTAssertTrue(reopened.notifications.isEmpty)

        await reopened.recordDailyBranchCleanupCheck(
            repositoryURL: repository,
            branchNames: ["feature/two"],
            now: now.addingTimeInterval(60)
        )
        XCTAssertTrue(reopened.notifications.isEmpty)
    }

    func testPullRequestCreatedPersistsAndActivatesPendingPullRequest() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let controller = AppNotificationController(dataStore: fixture.store)
        let repository = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        let pullRequest = PullRequestSummary(
            number: 42,
            title: "Add feature",
            state: .open,
            author: PullRequestAuthor(username: "octocat"),
            source: PullRequestBranchRef(label: "octocat:feature", ref: "feature", sha: nil),
            target: PullRequestBranchRef(label: "octocat:main", ref: "main", sha: nil),
            webURL: try XCTUnwrap(URL(string: "https://github.com/octocat/example/pull/42")),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        await controller.recordPullRequestCreated(pullRequest, repositoryURL: repository, remoteName: "upstream")

        let notification = try XCTUnwrap(controller.notifications.first)
        XCTAssertEqual(notification.kind, .pullRequestCreated)
        XCTAssertEqual(notification.pullRequest, pullRequest)
        XCTAssertEqual(notification.remoteName, "upstream")
        XCTAssertEqual(controller.unreadCount, 1)

        controller.activate(notification)
        XCTAssertEqual(controller.pendingPullRequest?.id, notification.id)
        XCTAssertNil(controller.pendingBranchCleanup)
        controller.consumePendingPullRequest(id: notification.id)
        XCTAssertNil(controller.pendingPullRequest)

        let reopenedStore = try await fixture.reopen()
        let reopened = AppNotificationController(dataStore: reopenedStore)
        await reopened.load()
        XCTAssertEqual(reopened.notifications.first?.pullRequest, pullRequest)
    }
}
