// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class AzureReposRemoteTests: XCTestCase {
    private let expected = AzureReposRemote(organization: "Trantienthanh1998", project: "ChatApp", repository: "ChatApp")

    func testParsesHTTPSRemoteWithEmbeddedUsername() {
        let remote = AzureReposRemote.parse("https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp")

        XCTAssertEqual(remote, expected)
        XCTAssertEqual(remote?.canonicalURL.absoluteString, "https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp")
        XCTAssertEqual(remote?.organizationURL.absoluteString, "https://dev.azure.com/trantienthanh1998")
    }

    func testParsesSSHRemotes() {
        XCTAssertEqual(AzureReposRemote.parse("git@ssh.dev.azure.com:v3/Trantienthanh1998/ChatApp/ChatApp"), expected)
        XCTAssertEqual(AzureReposRemote.parse("ssh://git@ssh.dev.azure.com/v3/Trantienthanh1998/ChatApp/ChatApp"), expected)
        XCTAssertEqual(
            AzureReposRemote.parse("Trantienthanh1998@vs-ssh.visualstudio.com:v3/Trantienthanh1998/ChatApp/ChatApp"),
            expected
        )
    }

    func testParsesLegacyVisualStudioRemotes() {
        let withCollection = AzureReposRemote.parse("https://trantienthanh1998.visualstudio.com/DefaultCollection/ChatApp/_git/ChatApp")
        let withoutCollection = AzureReposRemote.parse("https://trantienthanh1998.visualstudio.com/ChatApp/_git/ChatApp")

        XCTAssertEqual(withCollection?.organizationKey, "trantienthanh1998")
        XCTAssertEqual(withCollection?.project, "ChatApp")
        XCTAssertEqual(withCollection?.repository, "ChatApp")
        XCTAssertEqual(withoutCollection, withCollection)
    }

    func testProjectOmittedWhenItMatchesRepository() {
        let remote = AzureReposRemote.parse("https://dev.azure.com/Contoso/_git/Site")

        XCTAssertEqual(remote, AzureReposRemote(organization: "Contoso", project: "Site", repository: "Site"))
    }

    func testDecodesAndReencodesNamesWithSpaces() {
        let remote = AzureReposRemote.parse("https://dev.azure.com/acme/My%20Project/_git/My%20Repo")

        XCTAssertEqual(remote?.project, "My Project")
        XCTAssertEqual(remote?.repository, "My Repo")
        XCTAssertEqual(remote?.canonicalURL.absoluteString, "https://dev.azure.com/acme/My%20Project/_git/My%20Repo")
    }

    func testPullRequestURLs() {
        XCTAssertEqual(
            expected.pullRequestCreateURL(sourceBranch: "feature/login")?.absoluteString,
            "https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp/pullrequestcreate?sourceRef=feature%2Flogin"
        )
        XCTAssertEqual(
            expected.pullRequestsURL.absoluteString,
            "https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp/pullrequests"
        )
    }

    func testRejectsNonRepositoryURLs() {
        XCTAssertNil(AzureReposRemote.parse("https://dev.azure.com/Contoso/Web/Site"))
        XCTAssertNil(AzureReposRemote.parse("https://dev.azure.com/Contoso"))
        XCTAssertNil(AzureReposRemote.parse("https://dev.azure.com/Contoso/Web/_git"))
        XCTAssertNil(AzureReposRemote.parse("git@ssh.dev.azure.com:Contoso/Web/Site"))
        XCTAssertNil(AzureReposRemote.parse("https://github.com/octocat/Hello-World.git"))
        XCTAssertNil(AzureReposRemote.parse("https://dev.azure.com/Contoso/Web/_git/a%2Fb"))
    }

    func testOrganizationInput() {
        XCTAssertEqual(AzureReposRemote.organization(fromInput: "Trantienthanh1998"), "Trantienthanh1998")
        XCTAssertEqual(AzureReposRemote.organization(fromInput: " https://dev.azure.com/Trantienthanh1998/ChatApp "), "Trantienthanh1998")
        XCTAssertEqual(AzureReposRemote.organization(fromInput: "dev.azure.com/Trantienthanh1998"), "Trantienthanh1998")
        XCTAssertEqual(AzureReposRemote.organization(fromInput: "trantienthanh1998.visualstudio.com"), "trantienthanh1998")
    }

    func testRejectsInvalidOrganizationInput() {
        XCTAssertNil(AzureReposRemote.organization(fromInput: ""))
        XCTAssertNil(AzureReposRemote.organization(fromInput: "my org"))
        XCTAssertNil(AzureReposRemote.organization(fromInput: "https://github.com/octocat"))
        XCTAssertNil(AzureReposRemote.organization(fromInput: "http://dev.azure.com/Contoso"))
        XCTAssertNil(AzureReposRemote.organization(fromInput: "-contoso"))
        XCTAssertNil(AzureReposRemote.organization(fromInput: "https://dev.azure.com"))
    }
}
