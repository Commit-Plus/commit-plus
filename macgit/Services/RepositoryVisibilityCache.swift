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

struct CachedRepositoryVisibility: Codable, Equatable {
    let provider: GitProviderKind
    let host: String
    let owner: String
    let name: String
    let visibility: RepositoryVisibility
    let resolvedAt: Date

    init(
        repository: GitRepositoryIdentity,
        visibility: RepositoryVisibility,
        resolvedAt: Date
    ) {
        provider = repository.provider
        host = Self.normalizedHost(repository.hostURL)
        owner = repository.owner.lowercased()
        name = repository.name.lowercased()
        self.visibility = visibility
        self.resolvedAt = resolvedAt
    }

    var cacheKey: String {
        [provider.rawValue, host, owner, name].joined(separator: "|")
    }

    static func cacheKey(for repository: GitRepositoryIdentity) -> String {
        [
            repository.provider.rawValue,
            normalizedHost(repository.hostURL),
            repository.owner.lowercased(),
            repository.name.lowercased(),
        ].joined(separator: "|")
    }

    private static func normalizedHost(_ url: URL) -> String {
        (url.host(percentEncoded: false) ?? url.absoluteString).lowercased()
    }
}

@MainActor
protocol RepositoryVisibilityCaching {
    func cachedVisibility(
        for repository: GitRepositoryIdentity,
        maximumAge: TimeInterval,
        now: Date
    ) -> RepositoryVisibility?

    func save(
        _ visibility: RepositoryVisibility,
        for repository: GitRepositoryIdentity,
        resolvedAt: Date
    ) async
}

@MainActor
final class SQLiteRepositoryVisibilityCache: RepositoryVisibilityCaching {
    private let dataStore: LocalDataStore
    init(dataStore: LocalDataStore? = nil) { self.dataStore = dataStore ?? .shared }

    func cachedVisibility(for repository: GitRepositoryIdentity, maximumAge: TimeInterval, now: Date) -> RepositoryVisibility? {
        guard let record = try? dataStore.value(CachedRepositoryVisibility.self, in: "repositoryVisibility",
                                              id: CachedRepositoryVisibility.cacheKey(for: repository)),
              record.visibility == .public || record.visibility == .private,
              now.timeIntervalSince(record.resolvedAt) >= 0,
              now.timeIntervalSince(record.resolvedAt) <= maximumAge else { return nil }
        return record.visibility
    }

    func save(_ visibility: RepositoryVisibility, for repository: GitRepositoryIdentity, resolvedAt: Date) async {
        guard visibility == .public || visibility == .private else { return }
        let record = CachedRepositoryVisibility(repository: repository, visibility: visibility, resolvedAt: resolvedAt)
        do {
            try await dataStore.transaction { transaction in
                for (id, cached) in try transaction.values(CachedRepositoryVisibility.self, in: "repositoryVisibility")
                    where resolvedAt.timeIntervalSince(cached.resolvedAt) > 30 * 24 * 60 * 60 {
                    transaction.remove(in: "repositoryVisibility", id: id)
                }
                try transaction.set(record, in: "repositoryVisibility", id: record.cacheKey)
            }
        } catch {
            NSLog("Commit+ repository visibility cache could not be saved: %@", error.localizedDescription)
        }
    }
}
