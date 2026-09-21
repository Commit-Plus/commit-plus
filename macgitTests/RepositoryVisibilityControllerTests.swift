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

import Foundation
import XCTest
@testable import macgit

@MainActor
final class RepositoryVisibilityControllerTests: XCTestCase {
    func testRepositoryWithoutRemotesIsLocalWithoutProviderRequest() async {
        let service = FakeRepositoryVisibilityProvider()
        let controller = makeController(remotes: [], remoteURLs: [:], service: service)

        let visibility = await controller.resolve(repositoryURL: repositoryURL, accounts: [])

        XCTAssertEqual(visibility, .local)
        XCTAssertTrue(service.receivedTokens.isEmpty)
    }

    func testAnonymousPublicResultIsCached() async {
        let service = FakeRepositoryVisibilityProvider(results: [.success(.public)])
        let cache = FakeRepositoryVisibilityCache()
        let controller = makeController(service: service, cache: cache)

        let first = await controller.resolve(repositoryURL: repositoryURL, accounts: [])
        let second = await controller.resolve(repositoryURL: repositoryURL, accounts: [])

        XCTAssertEqual(first, .public)
        XCTAssertEqual(second, .public)
        XCTAssertEqual(service.receivedTokens.count, 1)
        XCTAssertEqual(cache.values.values.first?.visibility, .public)
    }

    func testPrivateRepositoryRetriesWithMatchingLocalToken() async {
        let service = FakeRepositoryVisibilityProvider(results: [
            .failure(.repositoryUnavailable),
            .success(.private),
        ])
        let account = makeAccount()
        let vault = FakeRepositoryVisibilityTokenVault(tokens: [account.id: token])
        let controller = makeController(service: service, tokenVault: vault)

        let visibility = await controller.resolve(
            repositoryURL: repositoryURL,
            accounts: [account]
        )

        XCTAssertEqual(visibility, .private)
        XCTAssertEqual(service.receivedTokens, [nil, token])
    }

    func testPrivateRemoteWinsOverPublicRemote() async {
        let service = FakeRepositoryVisibilityProvider(results: [
            .success(.public),
            .success(.private),
        ])
        let controller = makeController(
            remotes: ["origin", "private"],
            remoteURLs: [
                "origin": "https://github.com/octocat/public.git",
                "private": "https://github.com/octocat/private.git",
            ],
            service: service
        )

        let visibility = await controller.resolve(repositoryURL: repositoryURL, accounts: [])

        XCTAssertEqual(visibility, .private)
    }

    func testPublicAndUnsupportedRemoteResolveUnknown() async {
        let service = FakeRepositoryVisibilityProvider(results: [.success(.public)])
        let controller = makeController(
            remotes: ["origin", "mirror"],
            remoteURLs: [
                "origin": "https://github.com/octocat/public.git",
                "mirror": "https://example.com/octocat/private.git",
            ],
            service: service
        )

        let visibility = await controller.resolve(repositoryURL: repositoryURL, accounts: [])

        XCTAssertEqual(visibility, .unknown)
    }

    func testUnknownIsNotCachedAndRetriesLater() async {
        let service = FakeRepositoryVisibilityProvider(results: [
            .failure(.repositoryUnavailable),
            .success(.public),
        ])
        let cache = FakeRepositoryVisibilityCache()
        let controller = makeController(service: service, cache: cache)

        let first = await controller.resolve(repositoryURL: repositoryURL, accounts: [])
        let second = await controller.resolve(repositoryURL: repositoryURL, accounts: [])

        XCTAssertEqual(first, .unknown)
        XCTAssertEqual(second, .public)
        XCTAssertEqual(service.receivedTokens.count, 2)
        XCTAssertEqual(cache.values.values.first?.visibility, .public)
    }

    func testSQLiteCachePersistsOnlyConfirmedVisibility() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let cache = SQLiteRepositoryVisibilityCache(dataStore: fixture.store)
        let repository = githubRepository(name: "Hello-World")
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await cache.save(.unknown, for: repository, resolvedAt: now)
        XCTAssertNil(cache.cachedVisibility(for: repository, maximumAge: 900, now: now))

        await cache.save(.private, for: repository, resolvedAt: now)
        XCTAssertEqual(
            cache.cachedVisibility(for: repository, maximumAge: 900, now: now),
            .private
        )
        XCTAssertNil(
            cache.cachedVisibility(
                for: repository,
                maximumAge: 900,
                now: now.addingTimeInterval(901)
            )
        )
    }

    private let repositoryURL = URL(fileURLWithPath: "/tmp/repository")

    private func makeController(
        remotes: [String] = ["origin"],
        remoteURLs: [String: String] = [
            "origin": "https://github.com/octocat/Hello-World.git"
        ],
        service: FakeRepositoryVisibilityProvider,
        cache: FakeRepositoryVisibilityCache? = nil,
        tokenVault: GitProviderTokenVault = FakeRepositoryVisibilityTokenVault()
    ) -> RepositoryVisibilityController {
        RepositoryVisibilityController(
            services: [.github: service],
            tokenVault: tokenVault,
            cache: cache ?? FakeRepositoryVisibilityCache(),
            remotesProvider: { _ in remotes },
            remoteURLProvider: { _, remote in remoteURLs[remote] }
        )
    }

    private func makeAccount() -> GitProviderAccount {
        GitProviderAccount(
            id: "connection-1",
            macgitUID: "user-1",
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: "octocat",
            username: "octocat",
            displayName: nil,
            avatarURL: nil,
            scopes: ["repo"],
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }

    private var token: GitProviderToken {
        GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "bearer"
        )
    }

    private func githubRepository(name: String) -> GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            owner: "octocat",
            name: name
        )
    }
}

@MainActor
private final class FakeRepositoryVisibilityProvider: RepositoryVisibilityProviding {
    var results: [Result<RepositoryVisibility, RepositoryVisibilityProviderError>]
    private(set) var receivedTokens: [GitProviderToken?] = []

    init(results: [Result<RepositoryVisibility, RepositoryVisibilityProviderError>] = []) {
        self.results = results
    }

    func visibility(
        for repository: GitRepositoryIdentity,
        token: GitProviderToken?
    ) async throws -> RepositoryVisibility {
        receivedTokens.append(token)
        return try results.removeFirst().get()
    }
}

@MainActor
private final class FakeRepositoryVisibilityCache: RepositoryVisibilityCaching {
    var values: [String: CachedRepositoryVisibility] = [:]

    func cachedVisibility(
        for repository: GitRepositoryIdentity,
        maximumAge: TimeInterval,
        now: Date
    ) -> RepositoryVisibility? {
        values[CachedRepositoryVisibility.cacheKey(for: repository)]?.visibility
    }

    func save(
        _ visibility: RepositoryVisibility,
        for repository: GitRepositoryIdentity,
        resolvedAt: Date
    ) {
        guard visibility == .public || visibility == .private else { return }
        let value = CachedRepositoryVisibility(
            repository: repository,
            visibility: visibility,
            resolvedAt: resolvedAt
        )
        values[value.cacheKey] = value
    }
}

private final class FakeRepositoryVisibilityTokenVault: GitProviderTokenVault {
    var tokens: [String: GitProviderToken]

    init(tokens: [String: GitProviderToken] = [:]) {
        self.tokens = tokens
    }

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        tokens[account.id]
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {
        tokens[account.id] = token
    }

    func deleteToken(for account: GitProviderAccount) throws {
        tokens[account.id] = nil
    }
}
