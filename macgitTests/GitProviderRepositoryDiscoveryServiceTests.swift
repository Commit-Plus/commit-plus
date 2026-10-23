// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class GitProviderRepositoryDiscoveryServiceTests: XCTestCase {
    private let token = GitProviderToken(accessToken: "azure-pat", tokenType: "Basic")
    private let repositoriesBody = #"""
    {"count":3,"value":[
      {"name":"ChatApp","project":{"name":"ChatApp"},"remoteUrl":"https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp","sshUrl":"git@ssh.dev.azure.com:v3/Trantienthanh1998/ChatApp/ChatApp","isDisabled":false},
      {"name":"Archive","project":{"name":"ChatApp"},"remoteUrl":"https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/Archive","sshUrl":"git@ssh.dev.azure.com:v3/Trantienthanh1998/ChatApp/Archive","isDisabled":true},
      {"name":"My Repo","project":{"name":"Other Project"},"remoteUrl":"https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/Other%20Project/_git/My%20Repo","sshUrl":"git@ssh.dev.azure.com:v3/Trantienthanh1998/Other%20Project/My%20Repo"}
    ]}
    """#

    func testAzureDiscoveryListsEnabledRepositoriesWithHTTPSCloneURLs() async throws {
        let client = DiscoveryHTTPClient(body: repositoriesBody)

        let page = try await GitProviderRepositoryDiscoveryService(httpClient: client)
            .repositories(account: azureAccount(transportProtocol: .https), token: token, page: 1)

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://dev.azure.com/trantienthanh1998/_apis/git/repositories?api-version=7.1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data(":azure-pat".utf8).base64EncodedString())
        XCTAssertFalse(page.hasNextPage)
        XCTAssertEqual(page.repositories, [
            GitProviderDiscoveredRepository(name: "ChatApp/ChatApp", cloneURL: "https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp"),
            GitProviderDiscoveredRepository(name: "Other Project/My Repo", cloneURL: "https://dev.azure.com/Trantienthanh1998/Other%20Project/_git/My%20Repo"),
        ])
    }

    func testAzureDiscoveryUsesSSHCloneURLsForSSHAccounts() async throws {
        let page = try await GitProviderRepositoryDiscoveryService(httpClient: DiscoveryHTTPClient(body: repositoriesBody))
            .repositories(account: azureAccount(transportProtocol: .ssh), token: token, page: 1)

        XCTAssertEqual(page.repositories.first?.cloneURL, "git@ssh.dev.azure.com:v3/Trantienthanh1998/ChatApp/ChatApp")
    }

    func testAzureDiscoveryReturnsAllRepositoriesOnFirstPage() async throws {
        let client = DiscoveryHTTPClient(body: repositoriesBody)

        let page = try await GitProviderRepositoryDiscoveryService(httpClient: client)
            .repositories(account: azureAccount(transportProtocol: .https), token: token, page: 2)

        XCTAssertTrue(page.repositories.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testAzureDiscoveryRejectsExpiredToken() async {
        do {
            _ = try await GitProviderRepositoryDiscoveryService(httpClient: DiscoveryHTTPClient(body: "", status: 401))
                .repositories(account: azureAccount(transportProtocol: .https), token: token, page: 1)
            XCTFail("Expected token rejection")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The personal access token is invalid or expired. Reconnect the account.")
        }
    }

    private func azureAccount(transportProtocol: GitProviderTransportProtocol) -> GitProviderAccount {
        GitProviderAccount(
            id: "azure-account",
            macgitUID: "local",
            provider: .azureDevOps,
            hostURL: AzureReposRemote.organizationURL("Trantienthanh1998"),
            providerUserID: "user-1",
            username: "dev@example.com",
            displayName: nil,
            avatarURL: nil,
            scopes: [],
            permissions: ["authentication": "personalAccessToken"],
            tokenStatus: .valid,
            transportProtocol: transportProtocol,
            connectedAt: Date(timeIntervalSince1970: 0),
            lastValidatedAt: nil
        )
    }
}

private final class DiscoveryHTTPClient: GitProviderHTTPClient {
    private(set) var requests: [URLRequest] = []
    private let body: String
    private let status: Int

    init(body: String, status: Int = 200) {
        self.body = body
        self.status = status
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json; charset=utf-8"]
        )!
        return (Data(body.utf8), response)
    }
}
