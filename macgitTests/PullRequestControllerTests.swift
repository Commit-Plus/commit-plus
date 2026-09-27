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

@MainActor
final class PullRequestControllerTests: XCTestCase {
    func testLoadPullRequestsRequiresConnectedProviderAccount() async throws {
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: []),
            tokenVault: FakePullRequestTokenVault()
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(),
            services: [.github: FakePullRequestProvider()]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")

        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertEqual(controller.errorMessage, "Connect Account...")
        XCTAssertTrue(controller.needsAccountConnectionAction)
        XCTAssertEqual(controller.accountConnectionActionTitle, "Connect Account")
    }

    func testLoadPullRequestsExposesGitLabProviderForConnectionPrompt() async throws {
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: []),
            tokenVault: FakePullRequestTokenVault()
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(),
            services: [.gitlab: FakePullRequestProvider()]
        )

        await controller.loadPullRequests(remoteURLString: "https://gitlab.com/team/project.git")

        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertEqual(controller.errorMessage, "Connect Account...")
        XCTAssertEqual(controller.accountConnectionProvider, .gitlab)
        XCTAssertTrue(controller.needsAccountConnectionAction)
        XCTAssertEqual(controller.accountConnectionActionTitle, "Connect Account")
    }

    func testLoadPullRequestsRequiresReconnectWhenTokenIsMissing() async throws {
        let account = makeAccount()
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault()
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(),
            services: [.github: FakePullRequestProvider()]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")

        XCTAssertEqual(controller.errorMessage, "Reconnect...")
        XCTAssertTrue(controller.needsAccountConnectionAction)
        XCTAssertEqual(controller.accountConnectionActionTitle, "Reconnect")
    }

    func testLoadPullRequestsPromptsConnectWhenOnlySSHAccountExists() async throws {
        let account = makeAccount(
            id: "macgit-user-1:github:github.com:octocat",
            scopes: [],
            transportProtocol: .ssh
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault()
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(),
            services: [.github: FakePullRequestProvider()]
        )

        await controller.loadPullRequests(remoteURLString: "git@github.com:octocat/Hello-World.git")

        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertEqual(controller.errorMessage, "Connect Account...")
        XCTAssertTrue(controller.needsAccountConnectionAction)
        XCTAssertEqual(controller.accountConnectionActionTitle, "Connect Account")
    }

    func testLoadPullRequestsUsesOAuthAccountWhenSSHAccountAlsoExists() async throws {
        let sshAccount = makeAccount(
            id: "macgit-user-1:github:github.com:octocat",
            scopes: [],
            transportProtocol: .ssh
        )
        let oauthAccount = makeAccount(id: "macgit-user-1:github:github.com:583231")
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [sshAccount, oauthAccount]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [oauthAccount.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [oauthAccount.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "git@github.com:octocat/Hello-World.git")

        XCTAssertEqual(controller.items, [makeSummary()])
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.selectedProviderAccountID, oauthAccount.id)
        XCTAssertEqual(service.receivedToken, token)
    }

    func testLoadPullRequestsPublishesResults() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")

        XCTAssertEqual(controller.items, [makeSummary()])
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.selectedProviderAccountID, account.id)
        XCTAssertEqual(service.receivedRepository?.owner, "octocat")
        XCTAssertEqual(service.receivedRepository?.name, "Hello-World")
        XCTAssertEqual(service.receivedToken, token)
        XCTAssertEqual(service.receivedFilter, .open)
        XCTAssertEqual(service.receivedPage, 1)
        XCTAssertEqual(service.receivedPerPage, 30)
    }

    func testLoadPullRequestsPublishesPermissionError() async throws {
        let account = makeAccount()
        let token = makeToken()
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: FakePullRequestProvider(result: .failure(.permissionDenied))]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")

        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertEqual(
            controller.errorMessage,
            PullRequestProviderError.permissionDenied.localizedDescription
        )
    }

    func testOpenInBrowserUsesPullRequestWebURL() throws {
        var openedURL: URL?
        let controller = PullRequestController(
            providerAccountController: GitProviderAccountController(
                store: FakePullRequestAccountStore(accounts: []),
                tokenVault: FakePullRequestTokenVault()
            ),
            tokenVault: FakePullRequestTokenVault(),
            services: [:],
            openURL: { url in
                openedURL = url
                return true
            }
        )

        controller.openInBrowser(makeSummary())

        XCTAssertEqual(openedURL?.absoluteString, "https://github.com/octocat/Hello-World/pull/12")
    }

    func testVisibleItemsApplyStateAndCreatedByMeFilters() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([
            makeSummary(number: 12, state: .open, author: "octocat"),
            makeSummary(number: 13, state: .merged, author: "teammate"),
            makeSummary(number: 14, state: .closed, author: "octocat"),
        ]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        controller.stateFilter = .closed
        controller.createdByMeOnly = true

        XCTAssertEqual(controller.visibleItems.map(\.number), [14])
    }

    func testLoadNextPageRequestsNextProviderPage() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(
            result: .success([makeSummary(number: 12)]),
            hasNextPage: true
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-pagination")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        await controller.loadNextPage(repositoryURL: repositoryURL)

        XCTAssertEqual(service.receivedPage, 2)
        XCTAssertEqual(controller.currentPage, 2)
        XCTAssertTrue(controller.hasNextPage)
    }

    func testLoadPullRequestDetailPublishesSelectedDetail() async throws {
        let account = makeAccount()
        let token = makeToken()
        let detail = PullRequestDetail(
            summary: makeSummary(),
            body: "Adds pull request detail.",
            assignees: [PullRequestAuthor(username: "teammate", avatarURL: nil)],
            comments: [],
            changesURL: URL(string: "https://github.com/octocat/Hello-World/pull/12/files")!
        )
        let service = FakePullRequestProvider(
            result: .success([makeSummary()]),
            detailResult: .success(detail)
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.loadPullRequestDetail(makeSummary())

        XCTAssertEqual(controller.selectedDetail, detail)
        XCTAssertEqual(service.receivedDetailNumber, 12)
    }

    func testLoadPullRequestsUsesDiskCacheUntilForcedRefresh() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.loadPullRequests(
            remoteURLString: "https://github.com/octocat/Hello-World.git",
            forceRefresh: true
        )

        XCTAssertEqual(service.listCallCount, 2)
    }

    func testLoadPullRequestDetailUsesDiskCache() async throws {
        let account = makeAccount()
        let token = makeToken()
        let detail = PullRequestDetail(
            summary: makeSummary(),
            body: "Cached detail.",
            assignees: [],
            comments: [],
            changesURL: URL(string: "https://github.com/octocat/Hello-World/pull/12/files")!
        )
        let service = FakePullRequestProvider(
            result: .success([makeSummary()]),
            detailResult: .success(detail)
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.loadPullRequestDetail(makeSummary())
        await controller.loadPullRequestDetail(makeSummary())

        XCTAssertEqual(service.detailCallCount, 1)
        XCTAssertEqual(controller.selectedDetail, detail)
    }

    func testLoadPullRequestChangesPublishesAndCachesFiles() async throws {
        let account = makeAccount()
        let token = makeToken()
        let summary = makeSummary()
        let detail = PullRequestDetail(
            summary: summary,
            body: "Description",
            assignees: [],
            comments: [],
            changesURL: summary.webURL.appendingPathComponent("files")
        )
        let changes = [
            PullRequestChangedFile(
                path: "macgit/App.swift",
                previousPath: nil,
                status: .modified,
                additions: 2,
                deletions: 1,
                patch: "@@ -1 +1 @@\n-old\n+new",
                patchUnavailableReason: nil
            )
        ]
        let service = FakePullRequestProvider(
            result: .success([summary]),
            detailResult: .success(detail),
            changesResult: .success(changes)
        )
        let vault = FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: vault
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: vault,
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.loadPullRequestDetail(summary)
        await controller.loadPullRequestChanges(summary)
        await controller.loadPullRequestChanges(summary)

        XCTAssertEqual(controller.selectedChanges, changes)
        XCTAssertNil(controller.changesErrorMessage)
        XCTAssertEqual(service.changesCallCount, 1)
        XCTAssertEqual(service.receivedChangesNumber, 12)
    }

    func testCommentRetriesDetailRefreshUntilNewCommentIsVisible() async throws {
        let account = makeAccount()
        let token = makeToken()
        let summary = makeSummary()
        let author = PullRequestAuthor(username: "reviewer", avatarURL: nil)
        let existingComment = PullRequestComment(
            id: 1,
            author: author,
            body: "Existing comment.",
            webURL: summary.webURL,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newComment = PullRequestComment(
            id: 2,
            author: author,
            body: "Fresh comment.",
            webURL: summary.webURL,
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        func detail(comments: [PullRequestComment]) -> PullRequestDetail {
            PullRequestDetail(
                summary: summary,
                body: "Description",
                assignees: [],
                comments: comments,
                changesURL: summary.webURL.appendingPathComponent("files")
            )
        }
        let service = FakePullRequestProvider(
            result: .success([summary]),
            detailResults: [
                .success(detail(comments: [existingComment])),
                .success(detail(comments: [existingComment])),
                .success(detail(comments: [existingComment, newComment]))
            ]
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.loadPullRequestDetail(summary)
        await controller.comment(on: summary, body: "Fresh comment.")

        XCTAssertEqual(service.detailCallCount, 3)
        XCTAssertEqual(controller.selectedDetail?.comments, [existingComment, newComment])
    }

    func testOpenChangesInBrowserUsesDetailChangesURL() {
        var openedURL: URL?
        let controller = PullRequestController(
            providerAccountController: GitProviderAccountController(
                store: FakePullRequestAccountStore(accounts: []),
                tokenVault: FakePullRequestTokenVault()
            ),
            tokenVault: FakePullRequestTokenVault(),
            services: [:],
            openURL: { url in
                openedURL = url
                return true
            }
        )
        let detail = PullRequestDetail(
            summary: makeSummary(),
            body: "",
            assignees: [],
            comments: [],
            changesURL: URL(string: "https://github.com/octocat/Hello-World/pull/12/files")!
        )

        controller.openChangesInBrowser(detail)

        XCTAssertEqual(openedURL?.absoluteString, "https://github.com/octocat/Hello-World/pull/12/files")
    }

    func testPresentCreatePullRequestUsesCurrentBranchAndSuggestedTitle() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-actions")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "feature/pr-actions" },
            defaultBranchProvider: { _ in "develop" },
            localBranchesProvider: { _ in ["main", "feature/pr-actions"] }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        await controller.presentCreatePullRequest()

        XCTAssertEqual(controller.createDraftSeed?.sourceBranch, "feature/pr-actions")
        XCTAssertEqual(controller.createDraftSeed?.targetBranch, "develop")
        XCTAssertEqual(controller.createDraftSeed?.suggestedTitle, "Pr Actions")
    }

    func testPresentCreatePullRequestUsesRequestedSourceBranch() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-context-menu")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "main" },
            localBranchesProvider: { _ in ["main", "feature/context-menu-pr"] }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        await controller.presentCreatePullRequest(sourceBranch: "feature/context-menu-pr")

        XCTAssertEqual(controller.createDraftSeed?.sourceBranch, "feature/context-menu-pr")
        XCTAssertNil(controller.createDraftSeed?.targetBranch)
        XCTAssertEqual(controller.createDraftSeed?.suggestedTitle, "Context Menu Pr")
    }

    func testLoadCreateDraftSourceBranchesReturnsLocalBranchesFilteredByQuery() async throws {
        let account = makeAccount()
        let token = makeToken()
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-source-loader")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: FakePullRequestProvider(result: .success([makeSummary()]))],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            localBranchesProvider: { _ in ["main", "feature/a", "feature/b", "release/v1"] }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)

        let all = await controller.loadCreateDraftSourceBranches(query: "")
        XCTAssertEqual(all, ["feature/a", "feature/b", "main", "release/v1"])

        let filtered = await controller.loadCreateDraftSourceBranches(query: "feature")
        XCTAssertEqual(filtered, ["feature/a", "feature/b"])
    }

    func testLoadCreateDraftTargetBranchesMergesLocalAndRemoteAndRemovesDuplicates() async throws {
        let account = makeAccount()
        let token = makeToken()
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-target-loader")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: FakePullRequestProvider(result: .success([makeSummary()]))],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            localBranchesProvider: { _ in ["main", "feature/local"] },
            remoteBranchesProvider: { _ in ["main", "feature/remote", "hotfix/v2"] }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)

        let branches = await controller.loadCreateDraftTargetBranches(query: "")
        XCTAssertEqual(branches, ["feature/local", "feature/remote", "hotfix/v2", "main"])
    }

    func testPresentCreatePullRequestLoadsChangedFileCount() async throws {
        let account = makeAccount()
        let token = makeToken()
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-change-count")
        var receivedComparison: (source: String, target: String, remote: String?)?
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: FakePullRequestProvider(result: .success([makeSummary()]))],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "feature/change-count" },
            localBranchesProvider: { _ in ["main", "feature/change-count"] },
            changedFileCountProvider: { _, source, target, remote in
                receivedComparison = (source, target, remote)
                return 4
            }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        await controller.presentCreatePullRequest()

        XCTAssertNil(controller.createDraftChangedFileCount)

        await controller.loadCreateDraftChanges(sourceBranch: "feature/change-count", targetBranch: "main")

        XCTAssertEqual(controller.createDraftChangedFileCount, 4)
        XCTAssertFalse(controller.isLoadingCreateDraftChanges)
        XCTAssertNil(controller.createDraftChangesErrorMessage)
        XCTAssertEqual(receivedComparison?.source, "feature/change-count")
        XCTAssertEqual(receivedComparison?.target, "main")
        XCTAssertEqual(receivedComparison?.remote, "origin")
    }

    func testPresentCreatePullRequestLoadsParticipants() async throws {
        let account = makeAccount()
        let token = makeToken()
        let participants = [
            PullRequestParticipant(id: "z-user", username: "z-user", avatarURL: nil),
            PullRequestParticipant(id: "a-user", username: "a-user", avatarURL: nil),
        ]
        let service = FakePullRequestProvider(
            result: .success([makeSummary()]),
            participantsResult: .success(participants)
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "feature/pr-actions" },
            localBranchesProvider: { _ in ["main", "feature/pr-actions"] },
            changedFileCountProvider: { _, _, _, _ in 1 }
        )

        await controller.loadPullRequests(repositoryURL: URL(fileURLWithPath: "/tmp/macgit-pr-participants"))
        await controller.presentCreatePullRequest()

        XCTAssertEqual(controller.createDraftParticipants.map(\.username), ["a-user", "z-user"])
        XCTAssertFalse(controller.isLoadingCreateDraftParticipants)
        XCTAssertNil(controller.createDraftParticipantsErrorMessage)
    }

    func testCreatePullRequestChangeCountIsZeroWhenBranchesMatch() async throws {
        let account = makeAccount()
        let token = makeToken()
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        var providerWasCalled = false
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: FakePullRequestProvider()],
            changedFileCountProvider: { _, _, _, _ in
                providerWasCalled = true
                return 1
            }
        )

        await controller.loadCreateDraftChanges(sourceBranch: "main", targetBranch: "main")

        XCTAssertEqual(controller.createDraftChangedFileCount, 0)
        XCTAssertFalse(controller.isLoadingCreateDraftChanges)
        XCTAssertFalse(providerWasCalled)
    }

    func testCreatePullRequestRequiresValidDraft() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        let invalidDraft = try PullRequestDraft(
            repository: GitRepositoryIdentity(
                provider: .github,
                hostURL: URL(string: "https://github.com")!,
                owner: "octocat",
                name: "Hello-World"
            ),
            sourceBranch: "feature",
            targetBranch: "main",
            title: "Valid title",
            body: ""
        )
        var mutatedDraft = invalidDraft
        mutatedDraft.title = " "

        await controller.createPullRequest(mutatedDraft)

        XCTAssertEqual(controller.detailErrorMessage, "Pull request title is required.")
        XCTAssertNil(service.createdDraft)
    }

    func testCreatePullRequestRefreshesListAfterSuccess() async throws {
        let account = makeAccount()
        let token = makeToken()
        let createdSummary = makeSummary(number: 30)
        let service = FakePullRequestProvider(
            result: .success([createdSummary]),
            createResult: .success(createdSummary)
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-create")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "feature/pr-actions" },
            localBranchesProvider: { _ in ["main", "feature/pr-actions"] }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        let draft = try PullRequestDraft(
            repository: GitRepositoryIdentity(
                provider: .github,
                hostURL: URL(string: "https://github.com")!,
                owner: "octocat",
                name: "Hello-World"
            ),
            sourceBranch: "feature/pr-actions",
            targetBranch: "main",
            title: "Add provider-backed pull request actions",
            body: ""
        )

        await controller.createPullRequest(draft)

        XCTAssertEqual(service.createdDraft, draft)
        XCTAssertEqual(controller.items, [createdSummary])
    }

    func testCreatePullRequestReportsParticipantWarningWithoutFailingCreation() async throws {
        let account = makeAccount()
        let token = makeToken()
        let createdSummary = makeSummary(number: 31)
        let service = FakePullRequestProvider(
            result: .success([createdSummary]),
            createResult: .success(createdSummary),
            createWarnings: ["Reviewers could not be added."]
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )
        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        let draft = try PullRequestDraft(
            repository: GitRepositoryIdentity(
                provider: .github,
                hostURL: URL(string: "https://github.com")!,
                owner: "octocat",
                name: "Hello-World"
            ),
            sourceBranch: "feature/pr-actions",
            targetBranch: "main",
            title: "Create with warning",
            body: ""
        )

        await controller.createPullRequest(draft)

        XCTAssertEqual(controller.items, [createdSummary])
        XCTAssertEqual(
            controller.detailErrorMessage,
            "Pull request #31 was created, but Reviewers could not be added."
        )
    }

    func testCommentRequiresNonEmptyBody() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.comment(on: makeSummary(), body: "   ")

        XCTAssertEqual(controller.detailErrorMessage, "Pull request comment is required.")
        XCTAssertNil(service.createdCommentBody)
    }

    func testCheckoutPRFetchesProviderRefWhenNeeded() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary(number: 18)]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))

        var fetchedReference: (remote: String, reference: String, localBranch: String)?
        var checkedOutBranch: String?
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-checkout")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "main" },
            localBranchesProvider: { _ in ["main"] },
            fetchPullRequestRef: { remote, reference, localBranch, _, _ in
                fetchedReference = (remote, reference, localBranch)
            },
            checkoutBranch: { branch, _ in
                checkedOutBranch = branch
            }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        await controller.checkout(makeSummary(number: 18))

        XCTAssertEqual(fetchedReference?.remote, "origin")
        XCTAssertEqual(fetchedReference?.reference, "pull/18/head")
        XCTAssertEqual(fetchedReference?.localBranch, "pr/18")
        XCTAssertEqual(checkedOutBranch, "pr/18")
    }

    func testMergePullRequestInvalidatesAndRefreshesProviderState() async throws {
        let account = makeAccount()
        let token = makeToken()
        let mergedSummary = makeSummary(number: 18, state: .merged)
        let mergedDetail = PullRequestDetail(
            summary: mergedSummary,
            body: "Merged pull request.",
            assignees: [],
            comments: [],
            changesURL: URL(string: "https://github.com/octocat/Hello-World/pull/18/files")!
        )
        let service = FakePullRequestProvider(
            result: .success([makeSummary(number: 18)]),
            detailResult: .success(mergedDetail)
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.merge(makeSummary(number: 18))

        XCTAssertEqual(service.mergedPullRequestNumber, 18)
        XCTAssertEqual(controller.selectedDetail?.summary.state, .merged)
        XCTAssertEqual(service.listCallCount, 2)
    }

    func testRepositoryAIContextHydratesTheCurrentRepositoryBeforeLoadingPR() async throws {
        let account = makeAccount()
        let token = makeToken()
        let summary = makeSummary(number: 12)
        let detail = PullRequestDetail(
            summary: summary,
            body: "Review this change.",
            assignees: [],
            comments: [],
            changesURL: URL(string: "https://github.com/octocat/Hello-World/pull/12/files")!
        )
        let service = FakePullRequestProvider(
            result: .success([summary]),
            detailResult: .success(detail)
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" }
        )

        let context = try await controller.repositoryAIContext(
            number: summary.number,
            repositoryURL: URL(filePath: "/tmp/repository-ai-pr-context")
        )

        XCTAssertEqual(context.detail.summary.number, summary.number)
        XCTAssertEqual(service.receivedRepository?.owner, "octocat")
        XCTAssertEqual(service.receivedDetailNumber, summary.number)
    }

    func testDiskCacheSurvivesNewControllerAndSeparatesRepositoryFilterAndPage() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "cache.sqlite")
        let account = makeAccount()
        let vault = FakePullRequestTokenVault(tokensByAccountID: [account.id: makeToken()])
        let accounts = GitProviderAccountController(store: FakePullRequestAccountStore(accounts: [account]), tokenVault: vault)
        await accounts.reload()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let first = PullRequestController(providerAccountController: accounts, tokenVault: vault,
            services: [.github: service], diskCache: PullRequestDiskCache(url: url))
        let remote = "https://github.com/octocat/Hello-World.git"
        await first.loadPullRequests(remoteURLString: remote)
        first.releaseVisibleData()
        XCTAssertTrue(first.items.isEmpty)
        let reopened = PullRequestController(providerAccountController: accounts, tokenVault: vault,
            services: [.github: service], diskCache: PullRequestDiskCache(url: url))
        await reopened.loadPullRequests(remoteURLString: remote)
        XCTAssertEqual(service.listCallCount, 1)
        XCTAssertEqual(reopened.items.count, 1)
        await reopened.loadPullRequests(remoteURLString: remote, page: 2)
        reopened.stateFilter = .closed
        await reopened.loadPullRequests(remoteURLString: remote)
        await reopened.loadPullRequests(remoteURLString: "https://github.com/octocat/Another.git")
        XCTAssertEqual(service.listCallCount, 4)
    }

    func testDiskCacheSeparatesAccountsForSameRepository() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = PullRequestDiskCache(url: folder.appending(path: "cache.sqlite"))
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        for id in ["alice", "bob"] {
            let account = makeAccount(id: id)
            let vault = FakePullRequestTokenVault(tokensByAccountID: [account.id: makeToken()])
            let accounts = GitProviderAccountController(store: FakePullRequestAccountStore(accounts: [account]), tokenVault: vault)
            await accounts.reload()
            let controller = PullRequestController(providerAccountController: accounts, tokenVault: vault,
                services: [.github: service], diskCache: cache)
            await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        }
        XCTAssertEqual(service.listCallCount, 2)
    }

    func testClearingCacheDiscardsSuspendedListResponse() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = PullRequestDiskCache(url: folder.appending(path: "cache.sqlite"))
        let account = makeAccount()
        let vault = FakePullRequestTokenVault(tokensByAccountID: [account.id: makeToken()])
        let accounts = GitProviderAccountController(store: FakePullRequestAccountStore(accounts: [account]), tokenVault: vault)
        await accounts.reload()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let started = expectation(description: "Network list pending")
        var continuation: CheckedContinuation<Void, Never>?
        service.beforeListResponse = {
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        let controller = PullRequestController(providerAccountController: accounts, tokenVault: vault,
            services: [.github: service], diskCache: cache)
        let remote = "https://github.com/octocat/Hello-World.git"
        let old = Task { await controller.loadPullRequests(remoteURLString: remote) }
        await fulfillment(of: [started], timeout: 2)
        controller.clearSessionCaches()
        service.beforeListResponse = nil
        continuation?.resume()
        await old.value
        XCTAssertTrue(controller.items.isEmpty)
        await controller.loadPullRequests(remoteURLString: remote)
        XCTAssertEqual(service.listCallCount, 2)
        XCTAssertEqual(controller.items.count, 1)
    }

    private func makeAccount(
        id: String = "macgit-user-1:github:github.com:583231",
        scopes: [String] = ["repo", "read:user"],
        transportProtocol: GitProviderTransportProtocol = .https
    ) -> GitProviderAccount {
        GitProviderAccount(
            id: id,
            macgitUID: "macgit-user-1",
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: "583231",
            username: "octocat",
            displayName: "The Octocat",
            avatarURL: nil,
            scopes: scopes,
            permissions: [:],
            tokenStatus: .valid,
            transportProtocol: transportProtocol,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeToken() -> GitProviderToken {
        GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "bearer"
        )
    }

    private func makeSummary(
        number: Int = 12,
        state: PullRequestState = .open,
        author: String = "octocat"
    ) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Add provider-backed pull request read",
            state: state,
            author: PullRequestAuthor(username: author, avatarURL: nil),
            source: PullRequestBranchRef(label: "octocat:feature", ref: "feature", sha: "abc123"),
            target: PullRequestBranchRef(label: "octocat:main", ref: "main", sha: "def456"),
            webURL: URL(string: "https://github.com/octocat/Hello-World/pull/\(number)")!,
            createdAt: Date(timeIntervalSince1970: 1_779_900_000),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }
}

@MainActor
private final class FakePullRequestAccountStore: GitProviderAccountStore {
    let accountOwnerID: String
    private var accounts: [GitProviderAccount]

    init(accounts: [GitProviderAccount]) {
        self.accounts = accounts
        accountOwnerID = accounts.first?.macgitUID ?? "local-owner"
    }

    func accounts() async throws -> [GitProviderAccount] {
        accounts
    }

    func updateCloudAccount(uid: String?) async throws {
    }

    func save(_ account: GitProviderAccount) async throws {
        accounts.append(account)
    }

    func delete(accountID: String) async throws {
        accounts.removeAll { $0.id == accountID }
    }
}

private final class FakePullRequestTokenVault: GitProviderTokenVault {
    private var tokensByAccountID: [String: GitProviderToken]

    init(tokensByAccountID: [String: GitProviderToken] = [:]) {
        self.tokensByAccountID = tokensByAccountID
    }

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        tokensByAccountID[account.id]
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {
        tokensByAccountID[account.id] = token
    }

    func deleteToken(for account: GitProviderAccount) throws {
        tokensByAccountID.removeValue(forKey: account.id)
    }
}

private final class FakePullRequestProvider: PullRequestProviding {
    private let result: Result<[PullRequestSummary], PullRequestProviderError>
    private var detailResults: [Result<PullRequestDetail, PullRequestProviderError>]
    private let createResult: Result<PullRequestSummary, PullRequestProviderError>
    private let commentResult: Result<Void, PullRequestProviderError>
    private let mergeResult: Result<Void, PullRequestProviderError>
    private let changesResult: Result<[PullRequestChangedFile], PullRequestProviderError>
    private let participantsResult: Result<[PullRequestParticipant], PullRequestProviderError>
    private let createWarnings: [String]
    private let hasPreviousPage: Bool
    private let hasNextPage: Bool
    private(set) var receivedRepository: GitRepositoryIdentity?
    private(set) var receivedToken: GitProviderToken?
    private(set) var receivedFilter: PullRequestListFilter?
    private(set) var receivedPage: Int?
    private(set) var receivedPerPage: Int?
    private(set) var receivedDetailNumber: Int?
    private(set) var receivedChangesNumber: Int?
    var beforeListResponse: (() async -> Void)?
    private(set) var listCallCount = 0
    private(set) var detailCallCount = 0
    private(set) var changesCallCount = 0
    private(set) var createdDraft: PullRequestDraft?
    private(set) var createdCommentBody: String?
    private(set) var mergedPullRequestNumber: Int?

    init(
        result: Result<[PullRequestSummary], PullRequestProviderError> = .success([]),
        detailResult: Result<PullRequestDetail, PullRequestProviderError> = .failure(.providerMessage("No detail")),
        detailResults: [Result<PullRequestDetail, PullRequestProviderError>]? = nil,
        changesResult: Result<[PullRequestChangedFile], PullRequestProviderError> = .success([]),
        participantsResult: Result<[PullRequestParticipant], PullRequestProviderError> = .success([]),
        createResult: Result<PullRequestSummary, PullRequestProviderError> = .failure(.providerMessage("No create")),
        createWarnings: [String] = [],
        commentResult: Result<Void, PullRequestProviderError> = .success(()),
        mergeResult: Result<Void, PullRequestProviderError> = .success(()),
        hasPreviousPage: Bool = false,
        hasNextPage: Bool = false
    ) {
        self.result = result
        self.detailResults = detailResults ?? [detailResult]
        self.changesResult = changesResult
        self.participantsResult = participantsResult
        self.createResult = createResult
        self.createWarnings = createWarnings
        self.commentResult = commentResult
        self.mergeResult = mergeResult
        self.hasPreviousPage = hasPreviousPage
        self.hasNextPage = hasNextPage
    }

    func listPullRequests(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        filter: PullRequestListFilter,
        page: Int,
        perPage: Int
    ) async throws -> PullRequestListPage {
        listCallCount += 1
        await beforeListResponse?()
        receivedRepository = repository
        receivedToken = token
        receivedFilter = filter
        receivedPage = page
        receivedPerPage = perPage
        return PullRequestListPage(
            items: try result.get(),
            page: page,
            perPage: perPage,
            hasPreviousPage: hasPreviousPage,
            hasNextPage: hasNextPage
        )
    }

    func pullRequestParticipants(
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> [PullRequestParticipant] {
        receivedRepository = repository
        receivedToken = token
        return try participantsResult.get()
    }

    func pullRequestDetail(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> PullRequestDetail {
        detailCallCount += 1
        receivedRepository = repository
        receivedToken = token
        receivedDetailNumber = number
        let result = detailResults.isEmpty
            ? Result<PullRequestDetail, PullRequestProviderError>.failure(.providerMessage("No detail"))
            : detailResults.removeFirst()
        return try result.get()
    }

    func pullRequestChanges(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> [PullRequestChangedFile] {
        changesCallCount += 1
        receivedRepository = repository
        receivedToken = token
        receivedChangesNumber = number
        return try changesResult.get()
    }

    func createPullRequest(
        _ draft: PullRequestDraft,
        token: GitProviderToken
    ) async throws -> PullRequestCreationResult {
        createdDraft = draft
        receivedToken = token
        return PullRequestCreationResult(
            summary: try createResult.get(),
            warnings: createWarnings
        )
    }

    func createComment(
        body: String,
        on pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        createdCommentBody = body
        receivedRepository = repository
        receivedToken = token
        _ = pullRequest
        _ = try commentResult.get()
    }

    func mergePullRequest(
        _ pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        mergedPullRequestNumber = pullRequest.number
        receivedRepository = repository
        receivedToken = token
        _ = try mergeResult.get()
    }
}
