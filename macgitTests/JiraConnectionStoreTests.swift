// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

@MainActor
final class JiraConnectionStoreTests: XCTestCase {
    private var fixture: LocalDataStoreTestFixture!

    override func setUp() async throws {
        fixture = try LocalDataStoreTestFixture()
        try await fixture.store.prepare()
    }

    override func tearDown() async throws {
        fixture.cleanup()
    }

    func testSaveLoadAndRemovePerCommitPlusAccount() async throws {
        let store = LocalJiraConnectionStore(dataStore: fixture.store)
        let connection = JiraConnection.sample(uid: "uid-a")

        try await store.save(connection)
        let loaded = try await store.connection(for: "uid-a")
        XCTAssertEqual(loaded, connection)
        let other = try await store.connection(for: "uid-b")
        XCTAssertNil(other)

        let reopened = LocalJiraConnectionStore(dataStore: try await fixture.reopen())
        let persisted = try await reopened.connection(for: "uid-a")
        XCTAssertEqual(persisted, connection)

        try await store.removeConnection(for: "uid-a")
        let removed = try await store.connection(for: "uid-a")
        XCTAssertNil(removed)
    }

    func testTokenKeyIsScopedToCommitPlusAccount() {
        XCTAssertNotEqual(JiraConnection.sample(uid: "uid-a").id, JiraConnection.sample(uid: "uid-b").id)
    }

    func testFilterCodingSkipsSearchText() throws {
        var filter = JiraIssueFilter()
        filter.sprintScope = .sprint(id: 3, name: "Sprint 3")
        filter.projectKeys = ["PROJ"]
        filter.searchText = "login"

        let decoded = try JSONDecoder().decode(JiraIssueFilter.self, from: JSONEncoder().encode(filter))
        XCTAssertEqual(decoded.sprintScope, .sprint(id: 3, name: "Sprint 3"))
        XCTAssertEqual(decoded.projectKeys, ["PROJ"])
        XCTAssertEqual(decoded.searchText, "")
    }
}

extension JiraConnection {
    static func sample(uid: String = "uid-a", sprintFieldID: String? = "customfield_10020") -> JiraConnection {
        JiraConnection(
            macgitUID: uid,
            siteURL: URL(string: "https://acme.atlassian.net")!,
            email: "dev@example.com",
            accountID: "acc-1",
            displayName: "Dev",
            apiBase: .site,
            sprintFieldID: sprintFieldID,
            connectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

final class InMemoryJiraTokenStore: JiraTokenStoring {
    var tokens: [String: String] = [:]
    var failSave = false

    func token(for connection: JiraConnection) throws -> String? { tokens[connection.id] }

    func saveToken(_ token: String, for connection: JiraConnection) throws {
        if failSave { throw JiraError.storage("keychain") }
        tokens[connection.id] = token
    }

    func deleteToken(for connection: JiraConnection) throws { tokens[connection.id] = nil }
}

final class InMemoryJiraConnectionStore: JiraConnectionPersisting {
    var connections: [String: JiraConnection] = [:]
    var failSave = false

    func connection(for macgitUID: String) async throws -> JiraConnection? { connections[macgitUID] }

    func save(_ connection: JiraConnection) async throws {
        if failSave { throw JiraError.storage("disk") }
        connections[connection.macgitUID] = connection
    }

    func removeConnection(for macgitUID: String) async throws { connections[macgitUID] = nil }
}

final class StubJiraIssueService: JiraIssueServing {
    var validateResults: [Result<JiraValidatedAccount, JiraError>] = []
    var sprintField: String? = "customfield_10020"
    var searchHandler: ((String, String?) async throws -> JiraIssuePage)?
    private(set) var searchedJQL: [String] = []

    func validate(siteURL: URL, credential: JiraCredential) async throws -> JiraValidatedAccount {
        guard !validateResults.isEmpty else { throw JiraError.invalidCredentials }
        return try validateResults.removeFirst().get()
    }

    func sprintFieldID(baseURL: URL, credential: JiraCredential) async throws -> String? { sprintField }

    func searchIssues(
        baseURL: URL,
        credential: JiraCredential,
        jql: String,
        sprintFieldID: String?,
        pageToken: String?
    ) async throws -> JiraIssuePage {
        searchedJQL.append(jql)
        return try await searchHandler?(jql, pageToken) ?? JiraIssuePage(issues: [], nextPageToken: nil)
    }
}
