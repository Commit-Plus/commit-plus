// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class AzureDevOpsProviderAuthServiceTests: XCTestCase {
    private let token = GitProviderToken(accessToken: "azure-pat", tokenType: "Basic")

    func testFetchAccountReadsConnectionDataForOrganization() async throws {
        let client = AzureAuthHTTPClient(body: #"""
        {"authenticatedUser":{"id":"user-1","providerDisplayName":"Thanh Tran","properties":{"Account":{"$type":"System.String","$value":"dev@example.com"}}}}
        """#)
        let service = AzureDevOpsProviderAuthService(httpClient: client, now: { Date(timeIntervalSince1970: 10) })

        let account = try await service.fetchAccount(organization: "Trantienthanh1998", token: token, macgitUID: "local")

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://dev.azure.com/trantienthanh1998/_apis/connectionData")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data(":azure-pat".utf8).base64EncodedString())
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TFS-FedAuthRedirect"), "Suppress")
        XCTAssertEqual(account.provider, .azureDevOps)
        XCTAssertEqual(account.hostURL.absoluteString, "https://dev.azure.com/trantienthanh1998")
        XCTAssertEqual(account.providerUserID, "user-1")
        XCTAssertEqual(account.username, "dev@example.com")
        XCTAssertEqual(account.displayName, "Thanh Tran")
        XCTAssertEqual(account.permissions["authentication"], "personalAccessToken")
        XCTAssertEqual(account.id, "local:azure:dev.azure.com%2Ftrantienthanh1998:user-1")
        XCTAssertEqual(account.lastValidatedAt, Date(timeIntervalSince1970: 10))
    }

    func testFetchAccountFallsBackToDisplayNameWithoutAccountProperty() async throws {
        let client = AzureAuthHTTPClient(body: #"{"authenticatedUser":{"id":"user-1","providerDisplayName":"Thanh Tran"}}"#)

        let account = try await AzureDevOpsProviderAuthService(httpClient: client)
            .fetchAccount(organization: "contoso", token: token, macgitUID: "local")

        XCTAssertEqual(account.username, "Thanh Tran")
    }

    func testFetchAccountRejectsUnauthorizedToken() async {
        await assertRejected(AzureAuthHTTPClient(body: "", status: 401))
    }

    func testFetchAccountExplainsEachFailure() async {
        await assertFailure(
            AzureAuthHTTPClient(body: "<html>Sign in</html>", status: 203, contentType: "text/html"),
            "Azure DevOps did not accept the token and returned a sign-in page (HTTP 203, text/html)."
        )
        await assertFailure(
            AzureAuthHTTPClient(body: "<html>Sign in</html>", status: 200, contentType: "text/html; charset=utf-8"),
            "Azure DevOps did not accept the token and returned a sign-in page (HTTP 200, text/html; charset=utf-8)."
        )
        await assertFailure(
            AzureAuthHTTPClient(body: "{}", status: 403),
            "This token has no access to the contoso organization (HTTP 403)."
        )
        await assertFailure(
            AzureAuthHTTPClient(body: "{}"),
            "Azure DevOps returned an unexpected account response (HTTP 200, 2 bytes)."
        )
    }

    private func assertRejected(_ client: AzureAuthHTTPClient, file: StaticString = #filePath, line: UInt = #line) async {
        await assertFailure(client, AzureDevOpsProviderAuthService.rejectedTokenMessage, file: file, line: line)
    }

    private func assertFailure(
        _ client: AzureAuthHTTPClient,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await AzureDevOpsProviderAuthService(httpClient: client)
                .fetchAccount(organization: "contoso", token: token, macgitUID: "local")
            XCTFail("Expected a connection failure", file: file, line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, message, file: file, line: line)
        }
    }
}

private final class AzureAuthHTTPClient: GitProviderHTTPClient {
    private(set) var requests: [URLRequest] = []
    private let body: String
    private let status: Int
    private let contentType: String

    init(body: String, status: Int = 200, contentType: String = "application/json; charset=utf-8") {
        self.body = body
        self.status = status
        self.contentType = contentType
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (Data(body.utf8), response)
    }
}
