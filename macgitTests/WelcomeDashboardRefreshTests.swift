// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class WelcomeDashboardRefreshTests: XCTestCase {
    func testCachedRowsArePublishedBeforeFirstGitRead() async {
        let cache = WelcomeActivityCache(fileURL: nil)
        let missing = RecentRepository(url: URL(fileURLWithPath: "/missing"))
        let cached = RecentRepository(url: URL(fileURLWithPath: "/cached"))
        let days = WelcomeDashboardSnapshot.days(endingAt: .now)
        await cache.save(WelcomeActivityCacheEntry(days: days, savedAt: .now,
            activity: activity(cached, days)))
        var model: WelcomeDashboardModel!
        defer { model = nil }
        var loaded: [URL] = []
        model = WelcomeDashboardModel(activityCache: cache, activityLoader: { repository, days in
            loaded.append(repository.url)
            XCTAssertEqual(model.snapshot.repositories.map(\.url), [cached.url])
            return self.activity(repository, days)
        })
        await model.refresh(repositories: [missing, cached])
        XCTAssertEqual(loaded, [missing.url])
        XCTAssertEqual(model.snapshot.repositories.count, 2)
        XCTAssertFalse(model.isLoading)
    }

    func testTargetedInvalidationPreservesOtherActivityAndWarnings() async {
        let first = RecentRepository(url: URL(fileURLWithPath: "/first"))
        let second = RecentRepository(url: URL(fileURLWithPath: "/second"))
        var activityReads: [URL] = []
        var attentionReads: [URL] = []
        let model = WelcomeDashboardModel(activityCache: WelcomeActivityCache(fileURL: nil),
            activityLoader: { repository, days in
                activityReads.append(repository.url)
                return self.activity(repository, days)
            }, attentionLoader: { repository in
                attentionReads.append(repository.url)
                var status = WelcomeRepositoryAttention(url: repository.url, name: repository.name)
                status.conflicts = 1
                return status
            })
        let repositories = [first, second]
        await model.refresh(repositories: repositories)
        await model.refreshAttention(repositories: repositories)
        activityReads.removeAll()
        attentionReads.removeAll()
        model.invalidate(repositories: [first])
        await model.refresh(repositories: repositories)
        await model.refreshAttention(repositories: repositories)
        XCTAssertEqual(activityReads, [first.url])
        XCTAssertEqual(attentionReads, [first.url])
        XCTAssertEqual(Set(model.attention.map(\.url)), Set(repositories.map(\.url)))
        XCTAssertEqual(model.snapshot.repositories.count, 2)
    }

    func testAttentionIncludesRepositoriesOutsideActivityLimitAndPrunesRemovedOnes() async {
        let repositories = (0..<10).map { RecentRepository(url: URL(fileURLWithPath: "/repo-\($0)")) }
        var reads = 0
        let model = WelcomeDashboardModel(attentionLoader: { repository in
            reads += 1
            var status = WelcomeRepositoryAttention(url: repository.url, name: repository.name)
            status.behind = 1
            return status
        })
        await model.refreshAttention(repositories: repositories)
        XCTAssertEqual(reads, 10)
        XCTAssertEqual(model.attention.count, 10)
        await model.refreshAttention(repositories: Array(repositories.prefix(2)))
        XCTAssertEqual(reads, 10)
        XCTAssertEqual(model.attention.count, 2)
        model.invalidate(repositories: Array(repositories.prefix(2)), activity: false)
        await model.refreshAttention(repositories: Array(repositories.prefix(2)))
        XCTAssertEqual(reads, 12)
    }

    func testCancelledReadCannotPublishOrClearPendingInvalidation() async {
        let repository = RecentRepository(url: URL(fileURLWithPath: "/repo"))
        let cache = WelcomeActivityCache(fileURL: nil)
        let days = WelcomeDashboardSnapshot.days(endingAt: .now)
        var cachedActivity = activity(repository, days)
        cachedActivity.activityNote = "Cached"
        await cache.save(WelcomeActivityCacheEntry(days: days, savedAt: .now, activity: cachedActivity))
        let started = expectation(description: "Activity read started")
        var continuation: CheckedContinuation<WelcomeRepositoryActivity, Never>?
        var reads = 0
        let model = WelcomeDashboardModel(activityCache: cache,
            activityLoader: { repository, days in
                reads += 1
                if reads == 1 {
                    return await withCheckedContinuation {
                        continuation = $0
                        started.fulfill()
                    }
                }
                return self.activity(repository, days)
            })
        model.invalidate(repositories: [repository])
        let task = Task { await model.refresh(repositories: [repository]) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        continuation?.resume(returning: activity(repository, WelcomeDashboardSnapshot.days(endingAt: .now)))
        await task.value
        XCTAssertEqual(model.snapshot.repositories.first?.activityNote, "Cached")
        await model.refresh(repositories: [repository])
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(model.snapshot.repositories.count, 1)
        XCTAssertNil(model.snapshot.repositories.first?.activityNote)
    }

    func testForceRefreshBypassesCache() async {
        let repository = RecentRepository(url: URL(fileURLWithPath: "/repo"))
        var reads = 0
        let model = WelcomeDashboardModel(activityCache: WelcomeActivityCache(fileURL: nil),
            activityLoader: { repository, days in
                reads += 1
                return self.activity(repository, days)
            })
        await model.refresh(repositories: [repository])
        await model.refresh(repositories: [repository])
        XCTAssertEqual(reads, 1)
        await model.refresh(repositories: [repository], force: true)
        XCTAssertEqual(reads, 2)
    }

    private func activity(_ repository: RecentRepository, _ days: [Date]) -> WelcomeRepositoryActivity {
        WelcomeRepositoryActivity(url: repository.url, name: repository.name, commitsByDay: days.map { _ in [] })
    }
}
