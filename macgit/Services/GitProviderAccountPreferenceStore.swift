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

/// A stable, machine-independent key for the provider account used by a remote.
/// Tokens and SSH keys remain in local credential stores; this key only records
/// the non-secret account preference.
enum GitProviderAccountPreferenceKey {
    static func make(for identity: GitRemoteIdentity) -> String {
        [
            identity.provider.rawValue,
            identity.hostURL.host(percentEncoded: false)?.lowercased() ?? "",
            identity.ownerPath,
            identity.repositoryName,
        ].joined(separator: "|")
    }
}

@MainActor
final class GitProviderAccountPreferenceStore {
    static let shared = GitProviderAccountPreferenceStore()
    private let dataStore: LocalDataStore
    init(dataStore: LocalDataStore? = nil) { self.dataStore = dataStore ?? .shared }

    var preferences: [String: String] {
        (try? dataStore.values(String.self, in: "providerPreferences")) ?? [:]
    }

    func accountID(for identity: GitRemoteIdentity) -> String? {
        preferences[GitProviderAccountPreferenceKey.make(for: identity)]
    }

    func update(accountID: String?, for identity: GitRemoteIdentity) async throws {
        try await update(accountID: accountID, forPreferenceKey: GitProviderAccountPreferenceKey.make(for: identity))
    }

    func update(accountID: String?, forPreferenceKey preferenceKey: String) async throws {
        try await dataStore.transaction { transaction in
            if let accountID, !accountID.isEmpty {
                try transaction.set(accountID, in: "providerPreferences", id: preferenceKey)
            } else {
                transaction.remove(in: "providerPreferences", id: preferenceKey)
            }
        }
    }

    func replacePreferences(_ preferences: [String: String]) async throws {
        try await dataStore.transaction { transaction in
            for key in try transaction.values(String.self, in: "providerPreferences").keys {
                transaction.remove(in: "providerPreferences", id: key)
            }
            for (key, value) in preferences where !value.isEmpty {
                try transaction.set(value, in: "providerPreferences", id: key)
            }
        }
    }
}
