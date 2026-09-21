//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import XCTest
@testable import macgit

final class WelcomeActivityCacheTests: XCTestCase {
    func testCacheRemainsValidUntilLocalMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let savedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 1)))
        let midnight = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: savedAt)))
        let days = WelcomeDashboardSnapshot.days(endingAt: savedAt, calendar: calendar)
        let entry = makeEntry(days: days, now: savedAt)
        XCTAssertTrue(entry.isValid(for: days, now: midnight.addingTimeInterval(-1), calendar: calendar))
        XCTAssertFalse(entry.isValid(for: days, now: midnight, calendar: calendar))
        XCTAssertFalse(entry.isValid(for: days, now: savedAt.addingTimeInterval(-1), calendar: calendar))
        let nextDays = WelcomeDashboardSnapshot.days(endingAt: midnight, calendar: calendar)
        XCTAssertFalse(entry.isValid(for: nextDays, now: savedAt, calendar: calendar))
        let lateEntry = makeEntry(days: days, now: midnight.addingTimeInterval(-60))
        XCTAssertFalse(lateEntry.isValid(for: nextDays, now: midnight, calendar: calendar))
    }

    func testCacheUsesCalendarDayOnLongDaylightSavingDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let savedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let midnight = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: savedAt))
        let days = WelcomeDashboardSnapshot.days(endingAt: savedAt, calendar: calendar)
        let entry = makeEntry(days: days, now: savedAt)
        XCTAssertTrue(entry.isValid(for: days, now: savedAt.addingTimeInterval(24 * 60 * 60), calendar: calendar))
        XCTAssertFalse(entry.isValid(for: days, now: midnight, calendar: calendar))
    }

    func testSavedActivitySurvivesANewCacheInstance() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("cache.json")
        let now = Date.now
        let days = WelcomeDashboardSnapshot.days(endingAt: now)
        let entry = makeEntry(days: days, now: now)
        let first = WelcomeActivityCache(fileURL: file)
        await first.save(entry)
        let reopened = WelcomeActivityCache(fileURL: file)
        let cached = await reopened.entry(for: entry.activity.url, days: days, now: now)
        XCTAssertEqual(cached?.activity.commitsByDay, entry.activity.commitsByDay)
        XCTAssertEqual(cached?.activity.behindCount, 2)
        XCTAssertEqual(cached?.savedAt, now)
        let other = await reopened.entry(for: URL(fileURLWithPath: "/another"), days: days, now: now)
        XCTAssertNil(other)
    }

    func testCorruptCacheFallsBackToAMiss() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not json".utf8).write(to: file)
        let cache = WelcomeActivityCache(fileURL: file)
        let value = await cache.entry(for: URL(fileURLWithPath: "/repo"),
                                      days: WelcomeDashboardSnapshot.days(endingAt: .now), now: .now)
        XCTAssertNil(value)
    }

    private func makeEntry(days: [Date], now: Date) -> WelcomeActivityCacheEntry {
        var commits = days.map { _ in Set<String>() }
        commits[0] = ["commit-hash"]
        var activity = WelcomeRepositoryActivity(url: URL(fileURLWithPath: "/repo"), name: "Repo", commitsByDay: commits)
        activity.behindCount = 2
        return WelcomeActivityCacheEntry(days: days, savedAt: now, activity: activity)
    }
}
