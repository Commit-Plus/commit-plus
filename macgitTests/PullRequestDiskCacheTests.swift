// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class PullRequestDiskCacheTests: XCTestCase {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PRDiskCache-\(UUID().uuidString)/cache.sqlite")
    }

    func testPersistenceAcrossInstancesAndTTL() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = PullRequestDiskCache(url: url)
        let now = Date.now
        let epoch = await first.generation()
        await first.save(["one", "two"], key: "list", accountID: "alice", kind: "list", ttl: 60, generation: epoch, now: now)
        let second = PullRequestDiskCache(url: url)
        let nextEpoch = await second.generation()
        let cached = await second.value([String].self, key: "list", generation: nextEpoch, now: now.addingTimeInterval(59))
        XCTAssertEqual(cached, ["one", "two"])
        let expired = await second.value([String].self, key: "list", generation: nextEpoch, now: now.addingTimeInterval(60))
        XCTAssertNil(expired)
    }

    func testAccountRemovalRejectsLateWriteAndPreservesOtherAccount() async {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = PullRequestDiskCache(url: url)
        let epoch = await cache.generation()
        await cache.save("alice", key: "a", accountID: "alice", kind: "detail", ttl: 60, generation: epoch)
        await cache.save("bob", key: "b", accountID: "bob", kind: "detail", ttl: 60, generation: epoch)
        await cache.remove(accountID: "alice")
        await cache.save("late alice response", key: "a", accountID: "alice", kind: "detail", ttl: 60, generation: epoch)
        let current = await cache.generation()
        let alice = await cache.value(String.self, key: "a", generation: current)
        let bob = await cache.value(String.self, key: "b", generation: current)
        XCTAssertNil(alice)
        XCTAssertEqual(bob, "bob")
    }

    func testEvictsOldestPayloadAndSkipsOversizedReplacement() async {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = PullRequestDiskCache(url: url, maximumBytes: 100, maximumEntryBytes: 80)
        let epoch = await cache.generation()
        let now = Date.now
        let payload = String(repeating: "x", count: 60)
        await cache.save(payload, key: "old", accountID: "a", kind: "list", ttl: 60, generation: epoch, now: now)
        await cache.save(payload, key: "new", accountID: "a", kind: "list", ttl: 60, generation: epoch, now: now.addingTimeInterval(1))
        let old = await cache.value(String.self, key: "old", generation: epoch, now: now.addingTimeInterval(2))
        let new = await cache.value(String.self, key: "new", generation: epoch, now: now.addingTimeInterval(2))
        XCTAssertNil(old)
        XCTAssertEqual(new, payload)
        await cache.save(String(repeating: "z", count: 100), key: "new", accountID: "a", kind: "list", ttl: 60, generation: epoch)
        let oversized = await cache.value(String.self, key: "new", generation: epoch)
        XCTAssertNil(oversized)
    }

    func testCorruptionFallsBackToMissAndClearRepairsCache() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid SQLite".utf8).write(to: url)
        let cache = PullRequestDiskCache(url: url)
        let epoch = await cache.generation()
        let value = await cache.value(String.self, key: "key", generation: epoch)
        XCTAssertNil(value)
        await cache.remove()
        let current = await cache.generation()
        await cache.save("recovered", key: "key", accountID: "a", kind: "list", ttl: 60, generation: current)
        let recovered = await cache.value(String.self, key: "key", generation: current)
        XCTAssertEqual(recovered, "recovered")
    }

    func testInvalidationTargetsKindAndPRNumber() async {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = PullRequestDiskCache(url: url)
        let epoch = await cache.generation()
        await cache.save("list", key: "list", accountID: "a", kind: "list", ttl: 60, generation: epoch)
        await cache.save("one", key: "one", accountID: "a", kind: "detail", number: 1, ttl: 60, generation: epoch)
        await cache.save("two", key: "two", accountID: "a", kind: "detail", number: 2, ttl: 60, generation: epoch)
        await cache.remove(kind: "detail", number: 1)
        let current = await cache.generation()
        let list = await cache.value(String.self, key: "list", generation: current)
        let one = await cache.value(String.self, key: "one", generation: current)
        let two = await cache.value(String.self, key: "two", generation: current)
        XCTAssertEqual(list, "list")
        XCTAssertNil(one)
        XCTAssertEqual(two, "two")
    }
}
