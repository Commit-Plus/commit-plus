// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class SelfHostedGitProviderTests: XCTestCase {
    func testConfiguredServersPreservePortAndGitLabSubpath() throws {
        let server = try XCTUnwrap(GitProviderHost.configured(kind: .gitlab, value: " source.company.test:8443/gitlab/ "))
        XCTAssertEqual(server.baseURL.absoluteString, "https://source.company.test:8443/gitlab")
        XCTAssertFalse(GitProviderHost.accountHostIdentifier(server.baseURL).contains("/"))
        XCTAssertEqual(server.apiURL.absoluteString, "https://source.company.test:8443/gitlab/api/v4")
        for value in ["http://source.test", "ftp://source.test", "https://user:secret@source.test", "https://source.test?token=secret", "https://source.test/#fragment", "bad host"] {
            XCTAssertNil(GitProviderHost.configured(kind: .gitlab, value: value))
        }
        XCTAssertNil(GitProviderHost.configured(kind: .github, value: "https://source.test/unexpected"))
        XCTAssertEqual(GitProviderHost.githubDotCom.apiURL.absoluteString, "https://api.github.com")
        XCTAssertEqual(GitProviderHost.gitlabDotCom.apiURL.absoluteString, "https://gitlab.com/api/v4")
    }

    func testEnterpriseHTTPSAndSSHRecognizedWithoutProviderNameInHostname() throws {
        let server = try XCTUnwrap(GitProviderHost.configured(kind: .github, value: "https://source.company.test"))
        for remote in ["https://source.company.test/team/project.git", "git@source.company.test:team/project.git", "ssh://git@source.company.test:2222/team/project.git"] {
            let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(from: remote, knownHosts: [server]))
            XCTAssertEqual(identity.provider, .github)
            XCTAssertEqual(identity.ownerPath, "team")
            XCTAssertEqual(identity.hostURL, server.baseURL)
        }
        XCTAssertNil(GitRemoteIdentityResolver.identity(from: "https://source.company.test:8443/team/project.git", knownHosts: [server]))
    }

    func testGitLabSubpathExcludedFromProjectNamespace() throws {
        let server = try XCTUnwrap(GitProviderHost.configured(kind: .gitlab, value: "https://source.company.test:8443/gitlab"))
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(from: "https://source.company.test:8443/gitlab/team/subgroup/project.git", knownHosts: [server]))
        XCTAssertEqual(identity.ownerPath, "team/subgroup")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://source.company.test:8443/gitlab/team/subgroup/project.git")
        XCTAssertNil(GitRemoteIdentityResolver.identity(from: "https://source.company.test:8443/other/team/project.git", knownHosts: [server]))
        let ssh = try XCTUnwrap(GitRemoteIdentityResolver.identity(from: "git@source.company.test:team/project.git", knownHosts: [server]))
        XCTAssertEqual(ssh.ownerPath, "team")
    }

    func testVaultAndCredentialMatchingIsolateInstallations() async throws {
        let root = account(.gitlab, "https://source.test")
        let subpath = account(.gitlab, "https://source.test/gitlab")
        let port = account(.gitlab, "https://source.test:8443")
        XCTAssertEqual(Set([root, subpath, port].map(GitProviderTokenVaultKey.key)).count, 3)
        let resolver = GitProviderCredentialResolver(accounts: [root, subpath, port], tokenVault: TestVault())
        XCTAssertEqual(resolver.matchingAccounts(for: "https://source.test:8443/team/project.git").map(\.id), [port.id])
        XCTAssertEqual(resolver.matchingAccounts(for: "https://source.test/gitlab/team/project.git").map(\.id), [subpath.id])
        let credential = try await resolver.credential(for: "https://source.test:9443/team/project.git")
        XCTAssertNil(credential)
    }

    func testEnterpriseProfileValidationUsesConfiguredAPI() async throws {
        let client = Client(body: #"{"id":42,"login":"enterprise-user"}"#)
        let service = GitHubProviderAuthService(configuration: .appConfiguration(), httpClient: client)
        let host = GitProviderHost(kind: .github, baseURL: URL(string: "https://source.test:8443")!)
        let account = try await service.fetchAccount(token: token, macgitUID: "local", host: host)
        XCTAssertEqual(client.requests.first?.url?.absoluteString, "https://source.test:8443/api/v3/user")
        XCTAssertEqual(account.hostURL, host.baseURL)
    }

    func testDiscoveryUsesGitLabSubpathAndPaginates() async throws {
        let client = Client(body: #"[{"path_with_namespace":"team/project","http_url_to_repo":"https://source.test/gitlab/team/project.git","ssh_url_to_repo":"git@source.test:team/project.git"}]"#, headers: ["X-Next-Page": "3"])
        let result = try await GitProviderRepositoryDiscoveryService(httpClient: client).repositories(account: account(.gitlab, "https://source.test/gitlab"), token: token, page: 2)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.path, "/gitlab/api/v4/projects")
        XCTAssertTrue(request.url?.query?.contains("page=2") == true)
        XCTAssertTrue(request.url?.query?.contains("membership=true") == true)
        XCTAssertTrue(result.hasNextPage)
        XCTAssertEqual(result.repositories.first?.name, "team/project")
    }

    func testEnterpriseDiscoveryAndVisibilityStayOnEnterpriseServer() async throws {
        let client = Client(body: #"[{"full_name":"team/project","clone_url":"https://source.test/team/project.git","ssh_url":"git@source.test:team/project.git"}]"#, headers: ["Link": "<https://source.test/api/v3/user/repos?page=2>; rel=\"next\""])
        let result = try await GitProviderRepositoryDiscoveryService(httpClient: client).repositories(account: account(.github, "https://source.test"), token: token, page: 1)
        XCTAssertEqual(client.requests.first?.url?.path, "/api/v3/user/repos")
        XCTAssertTrue(result.hasNextPage)
        let visibilityClient = Client(body: #"{"private":true}"#)
        let visibility = try await GitHubRepositoryVisibilityService(httpClient: visibilityClient).visibility(for: GitRepositoryIdentity(provider: .github, hostURL: URL(string: "https://source.test")!, owner: "team", name: "project"), token: token)
        XCTAssertEqual(visibility, .private)
        XCTAssertEqual(visibilityClient.requests.first?.url?.absoluteString, "https://source.test/api/v3/repos/team/project")
    }

    func testDiscoveryRejectsExpiredToken() async {
        let client = Client(body: "{}", status: 401)
        do {
            _ = try await GitProviderRepositoryDiscoveryService(httpClient: client).repositories(account: account(.github, "https://source.test"), token: token, page: 1)
            XCTFail("Expected token rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("invalid or expired")) }
    }

    private var token: GitProviderToken { GitProviderToken(accessToken: "test-token", tokenType: "Bearer") }
    private func account(_ provider: GitProviderKind, _ url: String) -> GitProviderAccount {
        GitProviderAccount(id: url, macgitUID: "local", provider: provider, hostURL: URL(string: url)!, providerUserID: "42", username: "user", displayName: nil, avatarURL: nil, scopes: [], permissions: ["authentication": "personalAccessToken"], tokenStatus: .valid, connectedAt: Date(), lastValidatedAt: nil)
    }
}

private final class Client: GitProviderHTTPClient {
    var requests: [URLRequest] = []
    let body: String
    let headers: [String: String]
    let status: Int
    init(body: String, headers: [String: String] = [:], status: Int = 200) { self.body = body; self.headers = headers; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

private struct TestVault: GitProviderTokenVault {
    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? { GitProviderToken(accessToken: "test-token", tokenType: "Bearer") }
    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {}
    func deleteToken(for account: GitProviderAccount) throws {}
}
