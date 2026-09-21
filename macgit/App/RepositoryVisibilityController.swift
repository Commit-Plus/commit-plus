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

import Combine
import Foundation

@MainActor
final class RepositoryVisibilityController: ObservableObject {
    @Published private(set) var visibilityByRepositoryURL: [URL: RepositoryVisibility] = [:]
    @Published private(set) var resolvingRepositoryURLs: Set<URL> = []

    private let services: [GitProviderKind: any RepositoryVisibilityProviding]
    private let tokenVault: GitProviderTokenVault
    private let cache: RepositoryVisibilityCaching
    private let remotesProvider: (URL) async -> [String]
    private let remoteURLProvider: (URL, String) async -> String?
    private let cacheMaximumAge: TimeInterval

    init(
        services: [GitProviderKind: any RepositoryVisibilityProviding],
        tokenVault: GitProviderTokenVault,
        cache: RepositoryVisibilityCaching,
        remotesProvider: @escaping (URL) async -> [String] = { repositoryURL in
            await GitStatusService.shared.remotes(in: repositoryURL)
        },
        remoteURLProvider: @escaping (URL, String) async -> String? = { repositoryURL, remote in
            let value = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
            return value.isEmpty ? nil : value
        },
        cacheMaximumAge: TimeInterval = 15 * 60
    ) {
        self.services = services
        self.tokenVault = tokenVault
        self.cache = cache
        self.remotesProvider = remotesProvider
        self.remoteURLProvider = remoteURLProvider
        self.cacheMaximumAge = cacheMaximumAge
    }

    func resolve(
        repositoryURL: URL,
        accounts: [GitProviderAccount],
        forceRefresh: Bool = false
    ) async -> RepositoryVisibility {
        resolvingRepositoryURLs.insert(repositoryURL)
        defer { resolvingRepositoryURLs.remove(repositoryURL) }

        let remotes = await remotesProvider(repositoryURL)
        guard !remotes.isEmpty else {
            return publish(.local, for: repositoryURL)
        }

        let orderedRemotes = remotes.sorted { lhs, rhs in
            if lhs == "origin" { return true }
            if rhs == "origin" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        let knownGitLabHosts: Set<String> = Set(accounts.compactMap { account -> String? in
            guard account.provider == .gitlab else { return nil }
            return normalizedHost(account.hostURL)
        })
        var foundPublic = false
        var foundUnknown = false

        for remote in orderedRemotes {
            guard let remoteURL = await remoteURLProvider(repositoryURL, remote),
                  let identity = GitRemoteIdentityResolver.identity(
                    from: remoteURL,
                    knownGitLabHosts: knownGitLabHosts
                  ) else {
                foundUnknown = true
                continue
            }

            let repository = GitRepositoryIdentity(
                provider: identity.provider,
                hostURL: identity.hostURL,
                owner: identity.ownerPath,
                name: identity.repositoryName
            )
            let visibility = await resolve(
                repository: repository,
                accounts: accounts,
                forceRefresh: forceRefresh
            )
            switch visibility {
            case .private:
                return publish(.private, for: repositoryURL)
            case .public:
                foundPublic = true
            case .local, .unknown:
                foundUnknown = true
            }
        }

        if foundUnknown {
            return publish(.unknown, for: repositoryURL)
        }
        return publish(foundPublic ? .public : .unknown, for: repositoryURL)
    }

    func accessDecision(
        for feature: PlanFeature,
        repositoryURL: URL,
        accounts: [GitProviderAccount],
        entitlement: AccountEntitlement,
        policy: FeatureAccessPolicy,
        forceRefresh: Bool = false
    ) async -> FeatureAccessDecision {
        let visibility = await resolve(
            repositoryURL: repositoryURL,
            accounts: accounts,
            forceRefresh: forceRefresh
        )
        return FeatureAccessResolver(policy: policy).decision(
            for: feature,
            entitlement: entitlement,
            repositoryVisibility: visibility
        )
    }

    private func resolve(
        repository: GitRepositoryIdentity,
        accounts: [GitProviderAccount],
        forceRefresh: Bool
    ) async -> RepositoryVisibility {
        if !forceRefresh,
           let cached = cache.cachedVisibility(
            for: repository,
            maximumAge: cacheMaximumAge,
            now: .now
           ) {
            return cached
        }
        guard let service = services[repository.provider] else { return .unknown }

        if let anonymousResult = try? await service.visibility(for: repository, token: nil) {
            await save(anonymousResult, repository: repository)
            return anonymousResult
        }

        for account in matchingAccounts(for: repository, accounts: accounts) {
            guard account.tokenStatus == .valid else {
                continue
            }
            let token: GitProviderToken
            do {
                guard let storedToken = try tokenVault.readToken(for: account),
                      !storedToken.accessToken.isEmpty else {
                    continue
                }
                token = storedToken
            } catch {
                continue
            }
            if let authenticatedResult = try? await service.visibility(for: repository, token: token) {
                await save(authenticatedResult, repository: repository)
                return authenticatedResult
            }
        }
        return .unknown
    }

    private func save(
        _ visibility: RepositoryVisibility,
        repository: GitRepositoryIdentity
    ) async {
        await cache.save(visibility, for: repository, resolvedAt: .now)
    }

    private func matchingAccounts(
        for repository: GitRepositoryIdentity,
        accounts: [GitProviderAccount]
    ) -> [GitProviderAccount] {
        let host = normalizedHost(repository.hostURL)
        return accounts.filter {
            $0.provider == repository.provider && normalizedHost($0.hostURL) == host
        }
    }

    @discardableResult
    private func publish(
        _ visibility: RepositoryVisibility,
        for repositoryURL: URL
    ) -> RepositoryVisibility {
        visibilityByRepositoryURL[repositoryURL] = visibility
        return visibility
    }

    private func normalizedHost(_ url: URL) -> String {
        (url.host(percentEncoded: false) ?? url.absoluteString).lowercased()
    }
}
