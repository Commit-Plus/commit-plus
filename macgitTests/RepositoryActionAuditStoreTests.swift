// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class RepositoryActionAuditStoreTests: XCTestCase {
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "macgit-audit-\(UUID().uuidString)/audit.sqlite")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
        super.tearDown()
    }

    func testSummariesAreNewestFirstAndScopedToRepository() async {
        let store = RepositoryActionAuditStore(url: databaseURL, postsNotifications: false)
        await store.record(record(repository: "/repo/a", title: "Fetch origin"))
        await store.record(record(repository: "/repo/b", title: "Push origin"))
        await store.record(record(repository: "/repo/a", title: "Commit", origin: .user, status: .failed, output: "error: nope"))

        let summaries = await store.summaries(repositoryPath: "/repo/a")

        XCTAssertEqual(summaries.map(\.title), ["Commit", "Fetch origin"])
        XCTAssertEqual(summaries.first?.status, .failed)
        XCTAssertEqual(summaries.first?.summary, "error: nope")
        XCTAssertEqual(summaries.last?.origin, .system)
        XCTAssertEqual(summaries.last?.summary, "Already up to date")
    }

    func testEntryLoadsOutputAndTruncationFlag() async throws {
        let store = RepositoryActionAuditStore(url: databaseURL, postsNotifications: false)
        let large = String(repeating: "x", count: RepositoryActionAudit.outputByteLimit + 10)
        await store.record(record(repository: "/repo", title: "Fetch origin", output: large))
        await store.record(record(repository: "/repo", title: "Push origin", output: "To remote"))

        let summaries = await store.summaries(repositoryPath: "/repo")
        let truncatedEntry = await store.entry(id: summaries[1].id)
        let smallEntry = await store.entry(id: summaries[0].id)
        let truncated = try XCTUnwrap(truncatedEntry)
        let small = try XCTUnwrap(smallEntry)

        XCTAssertTrue(truncated.isOutputTruncated)
        XCTAssertEqual(truncated.output.utf8.count, RepositoryActionAudit.outputByteLimit)
        XCTAssertFalse(small.isOutputTruncated)
        XCTAssertEqual(small.output, "To remote")
        XCTAssertEqual(small.command, "fetch origin")
        XCTAssertEqual(small.summary, "To remote")
    }

    func testKeepsOnlyNewestRecordsPerRepository() async {
        let store = RepositoryActionAuditStore(url: databaseURL, postsNotifications: false)
        for index in 0..<(RepositoryActionAuditStore.maximumRecordsPerRepository + 5) {
            await store.record(record(repository: "/repo", title: "Fetch \(index)"))
        }
        await store.record(record(repository: "/other", title: "Kept"))

        let summaries = await store.summaries(repositoryPath: "/repo", limit: 5_000)

        XCTAssertEqual(summaries.count, RepositoryActionAuditStore.maximumRecordsPerRepository)
        XCTAssertEqual(summaries.first?.title, "Fetch \(RepositoryActionAuditStore.maximumRecordsPerRepository + 4)")
        XCTAssertEqual(summaries.last?.title, "Fetch 5")
        let other = await store.summaries(repositoryPath: "/other")
        XCTAssertEqual(other.count, 1)
    }

    func testNewSessionStartsEmpty() async {
        let first = RepositoryActionAuditStore(url: databaseURL, postsNotifications: false)
        await first.record(record(repository: "/repo", title: "Fetch origin"))
        let firstCount = await first.summaries(repositoryPath: "/repo").count
        XCTAssertEqual(firstCount, 1)

        let next = RepositoryActionAuditStore(url: databaseURL, postsNotifications: false)
        let nextCount = await next.summaries(repositoryPath: "/repo").count
        XCTAssertEqual(nextCount, 0)
    }

    func testRemoveSessionFileDeletesDatabase() async {
        let store = RepositoryActionAuditStore(url: databaseURL, postsNotifications: false)
        await store.record(record(repository: "/repo", title: "Fetch origin"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))

        RepositoryActionAuditStore.removeSessionFile(at: databaseURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    private func record(
        repository: String,
        title: String,
        origin: RepositoryActionAuditOrigin = .system,
        status: RepositoryActionAuditStatus = .succeeded,
        output: String = ""
    ) -> RepositoryActionAuditRecord {
        RepositoryActionAuditRecord(
            repositoryPath: repository,
            title: title,
            origin: origin,
            command: "fetch origin",
            output: output,
            status: status,
            finishedAt: .now,
            duration: 0.1
        )
    }
}
