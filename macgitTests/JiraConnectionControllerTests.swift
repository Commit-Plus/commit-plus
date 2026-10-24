// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

@MainActor
final class JiraConnectionControllerTests: XCTestCase {
    private var client: StubJiraIssueService!
    private var tokens: InMemoryJiraTokenStore!
    private var store: InMemoryJiraConnectionStore!
    private var controller: JiraConnectionController!

    private let account = JiraValidatedAccount(accountID: "acc-1", displayName: "Dev", email: "dev@example.com", apiBase: .site)

    override func setUp() async throws {
        client = StubJiraIssueService()
        tokens = InMemoryJiraTokenStore()
        store = InMemoryJiraConnectionStore()
        controller = JiraConnectionController(client: client, tokenStore: tokens, connectionStore: store)
        await controller.updateMacgitAccount(uid: "uid-a")
    }

    func testSignedOutCannotConnect() async {
        await controller.updateMacgitAccount(uid: nil)
        client.validateResults = [.success(account)]

        let connected = await controller.connect(site: "acme", email: "dev@example.com", token: "t")
        XCTAssertFalse(connected)
        XCTAssertEqual(controller.errorMessage, JiraError.notSignedIn.localizedDescription)
        XCTAssertTrue(store.connections.isEmpty)
    }

    func testConnectSavesMetadataAndToken() async {
        client.validateResults = [.success(account)]

        let connected = await controller.connect(site: "acme", email: " dev@example.com ", token: " t1 ")
        XCTAssertTrue(connected)
        let connection = try! XCTUnwrap(controller.connection)
        XCTAssertEqual(connection.siteURL, URL(string: "https://acme.atlassian.net"))
        XCTAssertEqual(connection.sprintFieldID, "customfield_10020")
        XCTAssertEqual(store.connections["uid-a"], connection)
        XCTAssertEqual(tokens.tokens[connection.id], "t1")
        XCTAssertEqual(controller.credential(), JiraCredential(email: "dev@example.com", token: "t1"))
    }

    func testRejectedTokenSavesNothing() async {
        client.validateResults = [.failure(.invalidCredentials)]

        let connected = await controller.connect(site: "acme", email: "dev@example.com", token: "bad")
        XCTAssertFalse(connected)
        XCTAssertEqual(controller.errorMessage, JiraError.invalidCredentials.localizedDescription)
        XCTAssertNil(controller.connection)
        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertTrue(tokens.tokens.isEmpty)
    }

    func testUnsupportedSiteIsRejectedBeforeAnyRequest() async {
        client.validateResults = [.success(account)]
        let connected = await controller.connect(site: "https://jira.example.com", email: "dev@example.com", token: "t")
        XCTAssertFalse(connected)
        XCTAssertEqual(controller.errorMessage, JiraError.unsupportedSite.localizedDescription)
        XCTAssertEqual(client.validateResults.count, 1, "validate must not be called")
    }

    func testMetadataFailureRollsBackToken() async {
        client.validateResults = [.success(account)]
        store.failSave = true

        let connected = await controller.connect(site: "acme", email: "dev@example.com", token: "t1")
        XCTAssertFalse(connected)
        XCTAssertTrue(tokens.tokens.isEmpty)
        XCTAssertNil(controller.connection)
    }

    func testSecondConnectionIsRefused() async {
        client.validateResults = [.success(account), .success(account)]
        await controller.connect(site: "acme", email: "dev@example.com", token: "t1")

        let second = await controller.connect(site: "other", email: "dev@example.com", token: "t2")
        XCTAssertFalse(second)
        XCTAssertEqual(controller.connection?.siteHost, "acme.atlassian.net")
    }

    func testInvalidReconnectKeepsOldToken() async {
        client.validateResults = [.success(account), .failure(.invalidCredentials)]
        await controller.connect(site: "acme", email: "dev@example.com", token: "t1")
        await controller.markNeedsReconnect()

        let reconnected = await controller.reconnect(token: "bad")
        XCTAssertFalse(reconnected)
        XCTAssertEqual(controller.credential()?.token, "t1")
        XCTAssertEqual(controller.connection?.needsReconnect, true)
    }

    func testValidReconnectReplacesTokenAndClearsFlag() async {
        client.validateResults = [.success(account), .success(account)]
        await controller.connect(site: "acme", email: "dev@example.com", token: "t1")
        await controller.markNeedsReconnect()
        XCTAssertEqual(store.connections["uid-a"]?.needsReconnect, true)

        let reconnected = await controller.reconnect(token: "t2")
        XCTAssertTrue(reconnected)
        XCTAssertEqual(controller.credential()?.token, "t2")
        XCTAssertEqual(controller.connection?.needsReconnect, false)
        XCTAssertEqual(store.connections["uid-a"]?.needsReconnect, false)
    }

    func testReconnectWithDifferentAccountIsRefused() async {
        var otherAccount = account
        otherAccount.accountID = "acc-2"
        client.validateResults = [.success(account), .success(otherAccount)]
        await controller.connect(site: "acme", email: "dev@example.com", token: "t1")

        let reconnected = await controller.reconnect(token: "t2")
        XCTAssertFalse(reconnected)
        XCTAssertEqual(controller.credential()?.token, "t1")
    }

    func testRemoveDeletesTokenAndMetadata() async {
        client.validateResults = [.success(account)]
        await controller.connect(site: "acme", email: "dev@example.com", token: "t1")

        await controller.remove()
        XCTAssertNil(controller.connection)
        XCTAssertTrue(tokens.tokens.isEmpty)
        XCTAssertTrue(store.connections.isEmpty)
    }

    func testDifferentCommitPlusAccountDoesNotSeeConnection() async {
        client.validateResults = [.success(account)]
        await controller.connect(site: "acme", email: "dev@example.com", token: "t1")

        await controller.updateMacgitAccount(uid: "uid-b")
        XCTAssertNil(controller.connection)
        XCTAssertNil(controller.credential())

        await controller.updateMacgitAccount(uid: "uid-a")
        XCTAssertEqual(controller.connection?.macgitUID, "uid-a")
    }
}
