// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class LocalDataOnDemandTests: XCTestCase {
    func testPrepareAndOnDemandReadsDoNotRetainUnrelatedPayloads() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        try await fixture.store.transaction {
            try $0.set(String(repeating: "large", count: 100_000), in: "unrelated", id: "large")
            try $0.set("selected", in: "repoSettings", id: "/selected")
        }
        let reopened = try await fixture.reopen()
        let resident: Set<String> = ["providerAccounts", "providerPreferences", "sshPaths"]
        XCTAssertEqual(reopened.residentCollectionNames, resident)
        let selected = try await reopened.readValue(String.self, in: "repoSettings", id: "/selected")
        XCTAssertEqual(selected, "selected")
        let snapshot = try await reopened.snapshot(collections: ["repoSettings"])
        XCTAssertEqual(Set(snapshot.records.keys), ["repoSettings"])
        XCTAssertEqual(reopened.residentCollectionNames, resident)
        XCTAssertThrowsError(try reopened.value(String.self, in: "unrelated", id: "large"))
    }

    func testUndeclaredTransactionReadFailsWithoutCommittingEarlierWrites() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        do {
            try await fixture.store.transaction { transaction in
                try transaction.set("must roll back", in: "writes", id: "one")
                _ = try transaction.values(String.self, in: "undeclared")
            }
            XCTFail("A missing read scope must never be treated as an empty collection")
        } catch LocalDataError.collectionNotLoaded(let collection) {
            XCTAssertEqual(collection, "undeclared")
        }
        let writes = try await fixture.store.readValues(String.self, in: "writes")
        XCTAssertTrue(writes.isEmpty)
    }

    func testConcurrentReadModifyWriteTransactionsAreSerialized() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let tasks = (0..<20).map { _ in
            Task {
                try await fixture.store.transaction(reading: ["counter"]) { transaction in
                    let count = try transaction.value(Int.self, in: "counter", id: "value") ?? 0
                    try transaction.set(count + 1, in: "counter", id: "value")
                }
            }
        }
        for task in tasks { try await task.value }
        let value = try await fixture.store.readValue(Int.self, in: "counter", id: "value")
        XCTAssertEqual(value, 20)
        let reopened = try await fixture.reopen()
        let persisted = try await reopened.readValue(Int.self, in: "counter", id: "value")
        XCTAssertEqual(persisted, 20)
    }

    func testResidentSnapshotUpdatesOnlyAfterSuccessfulCommit() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.transaction {
            try $0.set("account-one", in: "providerPreferences", id: "remote")
        }
        XCTAssertEqual(try fixture.store.value(String.self, in: "providerPreferences", id: "remote"), "account-one")
        try await fixture.store.transaction { $0.remove(in: "providerPreferences", id: "remote") }
        XCTAssertNil(try fixture.store.value(String.self, in: "providerPreferences", id: "remote"))
    }
}
