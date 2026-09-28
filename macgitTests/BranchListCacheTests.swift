//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
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

final class BranchListCacheTests: XCTestCase {
    func testValidEntryIsReturnedWithoutRunningLoaderAgain() async {
        let cache = BranchListCache()
        let calls = CallCounter()
        let repository = URL(fileURLWithPath: "/tmp/repo-a")
        let firstDate = Date(timeIntervalSince1970: 0)

        let first = await cache.values(for: .local(repository), now: firstDate) {
            await calls.increment()
            return ["main", "feature/a"]
        }
        let second = await cache.values(
            for: .local(repository),
            now: firstDate.addingTimeInterval(119)
        ) {
            await calls.increment()
            return ["different"]
        }
        let callCount = await calls.value

        XCTAssertEqual(first, ["main", "feature/a"])
        XCTAssertEqual(second, first)
        XCTAssertEqual(callCount, 1)
    }

    func testEntryExpiresAtTwoMinutes() async {
        let cache = BranchListCache()
        let calls = CallCounter()
        let repository = URL(fileURLWithPath: "/tmp/repo-a")
        let firstDate = Date(timeIntervalSince1970: 0)

        _ = await cache.values(for: .local(repository), now: firstDate) {
            await calls.increment()
            return ["main"]
        }
        let refreshed = await cache.values(
            for: .local(repository),
            now: firstDate.addingTimeInterval(120)
        ) {
            await calls.increment()
            return ["release"]
        }
        let callCount = await calls.value

        XCTAssertEqual(refreshed, ["release"])
        XCTAssertEqual(callCount, 2)
    }

    func testRepositoryInvalidationForcesLocalRediscovery() async {
        let cache = BranchListCache()
        let calls = CallCounter()
        let repository = URL(fileURLWithPath: "/tmp/repo-a")
        let now = Date(timeIntervalSince1970: 0)

        _ = await cache.values(for: .local(repository), now: now) {
            await calls.increment()
            return ["main"]
        }
        await cache.invalidate(repositoryURL: repository)
        let refreshed = await cache.values(for: .local(repository), now: now) {
            await calls.increment()
            return ["feature/new"]
        }
        let callCount = await calls.value

        XCTAssertEqual(refreshed, ["feature/new"])
        XCTAssertEqual(callCount, 2)
    }

    func testRemoteInvalidationDoesNotDiscardOtherRemote() async {
        let cache = BranchListCache()
        let repository = URL(fileURLWithPath: "/tmp/repo-a")
        let now = Date(timeIntervalSince1970: 0)
        let calls = CallCounter()

        _ = await cache.values(for: .remote(repository, "origin"), now: now) {
            await calls.increment()
            return ["main"]
        }
        _ = await cache.values(for: .remote(repository, "upstream"), now: now) {
            await calls.increment()
            return ["develop"]
        }
        await cache.invalidateRemote(repositoryURL: repository, remote: "origin")

        let origin = await cache.values(for: .remote(repository, "origin"), now: now) {
            await calls.increment()
            return ["release"]
        }
        let upstream = await cache.values(for: .remote(repository, "upstream"), now: now) {
            await calls.increment()
            return ["different"]
        }
        let callCount = await calls.value

        XCTAssertEqual(origin, ["release"])
        XCTAssertEqual(upstream, ["develop"])
        XCTAssertEqual(callCount, 3)
    }

    func testConcurrentRequestsShareOneLoader() async {
        let cache = BranchListCache()
        let calls = CallCounter()
        let repository = URL(fileURLWithPath: "/tmp/repo-a")

        let first = Task {
            await cache.values(for: .local(repository)) {
                await calls.increment()
                await Task.yield()
                return ["main"]
            }
        }
        await Task.yield()
        let second = Task {
            await cache.values(for: .local(repository)) {
                await calls.increment()
                return ["different"]
            }
        }

        let results = await (first.value, second.value)
        let callCount = await calls.value

        XCTAssertEqual(results.0, ["main"])
        XCTAssertEqual(results.1, ["main"])
        XCTAssertEqual(callCount, 1)
    }

    func testLeastRecentlyUsedEntryIsEvictedAtCapacity() async {
        let cache = BranchListCache(capacity: 2)
        let now = Date(timeIntervalSince1970: 0)
        let first = URL(fileURLWithPath: "/tmp/repo-first")
        let second = URL(fileURLWithPath: "/tmp/repo-second")
        let third = URL(fileURLWithPath: "/tmp/repo-third")

        _ = await cache.values(for: .local(first), now: now) { ["first"] }
        _ = await cache.values(for: .local(second), now: now) { ["second"] }
        _ = await cache.values(for: .local(first), now: now) { ["unexpected"] }
        _ = await cache.values(for: .local(third), now: now) { ["third"] }

        let retainedFirst = await cache.values(for: .local(first), now: now) { ["unexpected"] }
        let reloadedSecond = await cache.values(for: .local(second), now: now) { ["reloaded"] }

        XCTAssertEqual(reloadedSecond, ["reloaded"])
        XCTAssertEqual(retainedFirst, ["first"])
    }
}

private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
