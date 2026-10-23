//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import XCTest
@testable import macgit

final class GitRemoteIdentityResolverTests: XCTestCase {
    func testParsesHttpsGitHubRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://github.com/octocat/Hello-World.git"
        ))

        XCTAssertEqual(identity.provider, .github)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://github.com")
        XCTAssertEqual(identity.ownerPath, "octocat")
        XCTAssertEqual(identity.repositoryName, "Hello-World")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://github.com/octocat/Hello-World.git")
    }

    func testParsesSshGitHubRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "git@github.com:octocat/Hello-World.git"
        ))

        XCTAssertEqual(identity.provider, .github)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://github.com")
        XCTAssertEqual(identity.ownerPath, "octocat")
        XCTAssertEqual(identity.repositoryName, "Hello-World")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://github.com/octocat/Hello-World.git")
    }

    func testParsesGitLabSubgroupRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://gitlab.com/group/subgroup/project.git"
        ))

        XCTAssertEqual(identity.provider, .gitlab)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://gitlab.com")
        XCTAssertEqual(identity.ownerPath, "group/subgroup")
        XCTAssertEqual(identity.repositoryName, "project")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://gitlab.com/group/subgroup/project.git")
    }

    func testParsesSelfHostedGitLabRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "git@gitlab.example.com:platform/mobile/app.git"
        ))

        XCTAssertEqual(identity.provider, .gitlab)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://gitlab.example.com")
        XCTAssertEqual(identity.ownerPath, "platform/mobile")
        XCTAssertEqual(identity.repositoryName, "app")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://gitlab.example.com/platform/mobile/app.git")
    }

    func testParsesConfiguredSelfHostedGitLabRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://source.company.com/platform/mobile/app.git",
            knownGitLabHosts: ["source.company.com"]
        ))

        XCTAssertEqual(identity.provider, .gitlab)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://source.company.com")
        XCTAssertEqual(identity.ownerPath, "platform/mobile")
        XCTAssertEqual(identity.repositoryName, "app")
    }

    func testParsesHttpsBitbucketRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://trantienthanh2412@bitbucket.org/workspace/project.git"
        ))

        XCTAssertEqual(identity.provider, .bitbucket)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://bitbucket.org")
        XCTAssertEqual(identity.ownerPath, "workspace")
        XCTAssertEqual(identity.repositoryName, "project")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://bitbucket.org/workspace/project.git")
    }

    func testParsesSshBitbucketRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "git@bitbucket.org:workspace/project.git"
        ))

        XCTAssertEqual(identity.provider, .bitbucket)
        XCTAssertEqual(identity.ownerPath, "workspace")
        XCTAssertEqual(identity.repositoryName, "project")
    }

    func testUnsupportedHostReturnsNil() {
        XCTAssertNil(GitRemoteIdentityResolver.identity(from: "https://example.com/octocat/Hello-World.git"))
    }

    func testRemoteWithoutRepositoryNameReturnsNil() {
        XCTAssertNil(GitRemoteIdentityResolver.identity(from: "https://github.com/octocat"))
    }

    func testParsesAzureReposHTTPSRemoteWithEmbeddedUsername() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp"
        ))

        XCTAssertEqual(identity.provider, .azureDevOps)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://dev.azure.com/trantienthanh1998")
        XCTAssertEqual(identity.ownerPath, "ChatApp")
        XCTAssertEqual(identity.repositoryName, "ChatApp")
        XCTAssertEqual(
            identity.canonicalHTTPSURL.absoluteString,
            "https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp"
        )
    }

    func testAzureReposRemoteFormsShareIdentityAndPreferenceKey() throws {
        let remotes = [
            "https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp",
            "https://dev.azure.com/trantienthanh1998/ChatApp/_git/ChatApp",
            "git@ssh.dev.azure.com:v3/Trantienthanh1998/ChatApp/ChatApp",
            "ssh://git@ssh.dev.azure.com/v3/Trantienthanh1998/ChatApp/ChatApp",
            "https://trantienthanh1998.visualstudio.com/DefaultCollection/ChatApp/_git/ChatApp",
            "Trantienthanh1998@vs-ssh.visualstudio.com:v3/Trantienthanh1998/ChatApp/ChatApp",
        ]
        let identities = try remotes.map { try XCTUnwrap(GitRemoteIdentityResolver.identity(from: $0), $0) }
        let keys = Set(identities.map(GitProviderAccountPreferenceKey.make(for:)))

        XCTAssertEqual(keys.count, 1)
        XCTAssertTrue(identities.allSatisfy { $0.provider == .azureDevOps })
    }

    func testAzureReposRemoteResolvesWhenAzureAccountIsKnown() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://dev.azure.com/Contoso/Web/_git/Site",
            knownHosts: [GitProviderHost(kind: .azureDevOps, baseURL: AzureReposRemote.organizationURL("contoso"))]
        ))

        XCTAssertEqual(identity.provider, .azureDevOps)
        XCTAssertEqual(identity.repositoryName, "Site")
    }

    func testAzureURLWithoutGitSegmentIsNotRecognized() {
        XCTAssertNil(GitRemoteIdentityResolver.identity(from: "https://dev.azure.com/Contoso/Web/Site"))
    }
}
