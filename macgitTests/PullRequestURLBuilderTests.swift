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

final class PullRequestURLBuilderTests: XCTestCase {
    // MARK: - GitHub

    func testGitHubHTTPSURLIsBuiltForCompareView() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "https://github.com/octocat/Hello-World.git",
            branch: "feature"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://github.com/octocat/Hello-World/compare/feature?expand=1"
        )
    }

    func testGitHubSSHURLIsNormalizedToHTTPS() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "git@github.com:octocat/Hello-World.git",
            branch: "feature"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://github.com/octocat/Hello-World/compare/feature?expand=1"
        )
    }

    func testGitHubSSHProtocolURLIsNormalizedToHTTPS() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "ssh://git@github.com/octocat/Hello-World.git",
            branch: "feature"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://github.com/octocat/Hello-World/compare/feature?expand=1"
        )
    }

    func testGitHubEnterpriseHostIsRecognized() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "https://github.acme.com/team/repo.git",
            branch: "main"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://github.acme.com/team/repo/compare/main?expand=1"
        )
    }

    // MARK: - GitLab

    func testGitLabHTTPSURLIsBuiltForMergeRequestView() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "https://gitlab.com/group/subgroup/repo.git",
            branch: "feature"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://gitlab.com/group/subgroup/repo/-/merge_requests/new?merge_request%5Bsource_branch%5D=feature"
        )
    }

    func testGitLabSSHBranchWithSlashIsPercentEscaped() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "git@gitlab.com:group/repo.git",
            branch: "feature/nested"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://gitlab.com/group/repo/-/merge_requests/new?merge_request%5Bsource_branch%5D=feature/nested"
        )
    }

    // MARK: - Bitbucket

    func testBitbucketHTTPSURLIsBuiltForPullRequestView() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "https://bitbucket.org/team/repo.git",
            branch: "feature"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://bitbucket.org/team/repo/pull-requests/new?source=feature"
        )
    }

    // MARK: - Edge cases

    func testEmptyBranchReturnsNil() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "https://github.com/octocat/Hello-World.git",
            branch: ""
        )
        XCTAssertNil(url)
    }

    func testWhitespaceBranchReturnsNil() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "https://github.com/octocat/Hello-World.git",
            branch: "   "
        )
        XCTAssertNil(url)
    }

    func testEmptyRemoteURLReturnsNil() {
        let url = PullRequestURLBuilder.build(remoteURL: "", branch: "feature")
        XCTAssertNil(url)
    }

    func testUnrecognizedHostReturnsNil() {
        let url = PullRequestURLBuilder.build(
            remoteURL: "https://example.com/team/repo.git",
            branch: "feature"
        )
        XCTAssertNil(url)
    }

    func testCanBuildReturnsTrueForGitHubHTTPS() {
        XCTAssertTrue(PullRequestURLBuilder.canBuild(remoteURL: "https://github.com/octocat/Hello-World.git"))
    }

    func testCanBuildReturnsTrueForGitHubSSH() {
        XCTAssertTrue(PullRequestURLBuilder.canBuild(remoteURL: "git@github.com:octocat/Hello-World.git"))
    }

    func testCanBuildReturnsFalseForUnrecognizedHost() {
        XCTAssertFalse(PullRequestURLBuilder.canBuild(remoteURL: "https://example.com/team/repo.git"))
    }

    func testAzureReposRemotesBuildPullRequestCreateURL() {
        let expected = "https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp/pullrequestcreate?sourceRef=feature%2Flogin"
        for remote in [
            "https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp",
            "git@ssh.dev.azure.com:v3/Trantienthanh1998/ChatApp/ChatApp",
        ] {
            XCTAssertEqual(
                PullRequestURLBuilder.build(remoteURL: remote, branch: "feature/login")?.absoluteString,
                expected,
                remote
            )
            XCTAssertTrue(PullRequestURLBuilder.canBuild(remoteURL: remote), remote)
        }
    }
}
