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
}
