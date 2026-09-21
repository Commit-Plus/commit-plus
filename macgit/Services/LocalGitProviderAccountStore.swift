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

@MainActor
protocol GitProviderAccountLocalStore {
    var accountOwnerID: String { get }

    func accounts() throws -> [GitProviderAccount]
    func save(_ account: GitProviderAccount) async throws
    func delete(accountID: String) async throws -> GitProviderAccount?
    func remove(accountID: String) async throws
    func pendingDeletions() throws -> [GitProviderAccount]
    func clearPendingDeletion(_ account: GitProviderAccount) async throws
    func syncedIdentityKeys(uid: String) -> Set<String>
    func setSyncedIdentityKeys(_ keys: Set<String>, uid: String) async throws
}

@MainActor
final class SQLiteGitProviderAccountLocalStore: GitProviderAccountLocalStore {
    let accountOwnerID: String
    private let dataStore: LocalDataStore

    init(dataStore: LocalDataStore? = nil, defaults: UserDefaults = .standard) {
        self.dataStore = dataStore ?? .shared
        // Keep this installation identity stable: it also participates in credential keys.
        let key = "dev.thanhtran.macgit.localGitProviderAccountOwnerID"
        if let owner = defaults.string(forKey: key), !owner.isEmpty { accountOwnerID = owner }
        else {
            accountOwnerID = "local-\(UUID().uuidString)"
            defaults.set(accountOwnerID, forKey: key)
        }
    }

    func accounts() throws -> [GitProviderAccount] {
        try dataStore.values(GitProviderAccount.self, in: "providerAccounts").values.sorted { $0.connectedAt < $1.connectedAt }
    }

    func save(_ account: GitProviderAccount) async throws {
        try await dataStore.transaction { transaction in
            let identity = GitProviderAccountLocalIdentity(account)
            for (id, stored) in try transaction.values(GitProviderAccount.self, in: "providerAccounts")
                where id == account.id || GitProviderAccountLocalIdentity(stored) == identity {
                transaction.remove(in: "providerAccounts", id: id)
            }
            try transaction.set(account, in: "providerAccounts", id: account.id)
            for (id, deleted) in try transaction.values(GitProviderAccount.self, in: "providerDeletions")
                where GitProviderAccountLocalIdentity(deleted) == identity {
                transaction.remove(in: "providerDeletions", id: id)
            }
        }
    }

    func delete(accountID: String) async throws -> GitProviderAccount? {
        try await dataStore.transaction { transaction in
            guard let account = try transaction.value(GitProviderAccount.self, in: "providerAccounts", id: accountID) else { return nil }
            try Self.remove(account, from: &transaction)
            for (id, deleted) in try transaction.values(GitProviderAccount.self, in: "providerDeletions")
                where GitProviderAccountLocalIdentity(deleted) == GitProviderAccountLocalIdentity(account) {
                transaction.remove(in: "providerDeletions", id: id)
            }
            try transaction.set(account, in: "providerDeletions", id: account.id)
            return account
        }
    }

    func remove(accountID: String) async throws {
        try await dataStore.transaction { transaction in
            if let account = try transaction.value(GitProviderAccount.self, in: "providerAccounts", id: accountID) {
                try Self.remove(account, from: &transaction)
            }
        }
    }

    private static func remove(_ account: GitProviderAccount, from transaction: inout LocalDataTransaction) throws {
        transaction.remove(in: "providerAccounts", id: account.id)
        transaction.remove(in: "sshPaths", id: GitProviderSSHKeyStoreKey.storageKey(for: account))
        for (key, value) in try transaction.values(String.self, in: "providerPreferences") where value == account.id {
            transaction.remove(in: "providerPreferences", id: key)
        }
    }

    func pendingDeletions() throws -> [GitProviderAccount] {
        Array(try dataStore.values(GitProviderAccount.self, in: "providerDeletions").values)
    }

    func clearPendingDeletion(_ account: GitProviderAccount) async throws {
        try await dataStore.transaction { transaction in
            for (id, deleted) in try transaction.values(GitProviderAccount.self, in: "providerDeletions")
                where GitProviderAccountLocalIdentity(deleted) == GitProviderAccountLocalIdentity(account) {
                transaction.remove(in: "providerDeletions", id: id)
            }
        }
    }

    func syncedIdentityKeys(uid: String) -> Set<String> {
        Set((try? dataStore.value([String].self, in: "providerSyncedIdentities", id: uid)) ?? [])
    }

    func setSyncedIdentityKeys(_ keys: Set<String>, uid: String) async throws {
        try await dataStore.transaction { transaction in
            try transaction.set(keys.sorted(), in: "providerSyncedIdentities", id: uid)
        }
    }
}

@MainActor
final class LocalFirstGitProviderAccountStore: GitProviderAccountStore {
    var accountOwnerID: String { localStore.accountOwnerID }

    private let localStore: GitProviderAccountLocalStore
    private let cloudStore: GitProviderAccountCloudStore?
    private var cloudUID: String?
    private var cloudAccountIDsByLocalAccountID: [String: String] = [:]

    init(
        localStore: GitProviderAccountLocalStore? = nil,
        cloudStore: GitProviderAccountCloudStore?
    ) {
        self.localStore = localStore ?? SQLiteGitProviderAccountLocalStore()
        self.cloudStore = cloudStore
    }

    func accounts() async throws -> [GitProviderAccount] {
        try localStore.accounts()
    }

    func updateCloudAccount(uid: String?) async throws {
        cloudUID = uid
        cloudAccountIDsByLocalAccountID = [:]
        guard let uid, let cloudStore else { return }

        let initialLocalAccounts = try localStore.accounts()
        let cloudAccounts: [GitProviderAccount]
        do {
            cloudAccounts = try await cloudStore.accounts(forMacgitUID: uid)
        } catch {
            return
        }

        let pendingDeletions = try localStore.pendingDeletions()
        let pendingIdentities = Set(pendingDeletions.map(GitProviderAccountLocalIdentity.init))
        for deletedAccount in pendingDeletions {
            let identity = GitProviderAccountLocalIdentity(deletedAccount)
            if let cloudAccount = cloudAccounts.first(where: { GitProviderAccountLocalIdentity($0) == identity }) {
                do {
                    try await cloudStore.delete(accountID: cloudAccount.id, macgitUID: uid)
                    try await localStore.clearPendingDeletion(deletedAccount)
                } catch {
                    // Keep the tombstone so a stale cloud snapshot cannot restore the local deletion.
                }
            } else {
                try await localStore.clearPendingDeletion(deletedAccount)
            }
        }

        let visibleCloudAccounts = cloudAccounts.filter {
            !pendingIdentities.contains(GitProviderAccountLocalIdentity($0))
        }
        let visibleCloudIdentityKeys = Set(visibleCloudAccounts.map {
            GitProviderAccountLocalIdentity($0).storageKey
        })
        let previouslySyncedIdentityKeys = localStore.syncedIdentityKeys(uid: uid)
        for localAccount in initialLocalAccounts {
            let identityKey = GitProviderAccountLocalIdentity(localAccount).storageKey
            if previouslySyncedIdentityKeys.contains(identityKey),
               !visibleCloudIdentityKeys.contains(identityKey),
               !pendingIdentities.contains(GitProviderAccountLocalIdentity(localAccount)) {
                try await localStore.remove(accountID: localAccount.id)
            }
        }

        var mergedAccounts = try localStore.accounts()
        for cloudAccount in visibleCloudAccounts {
            let identity = GitProviderAccountLocalIdentity(cloudAccount)
            if let localAccount = mergedAccounts.first(where: {
                GitProviderAccountLocalIdentity($0) == identity
            }) {
                cloudAccountIDsByLocalAccountID[localAccount.id] = cloudAccount.id
            } else {
                try await localStore.save(cloudAccount)
                mergedAccounts.append(cloudAccount)
                cloudAccountIDsByLocalAccountID[cloudAccount.id] = cloudAccount.id
            }
        }

        var syncedIdentityKeys = visibleCloudIdentityKeys
        for account in mergedAccounts {
            if await mirrorToCloud(account, uid: uid) {
                syncedIdentityKeys.insert(GitProviderAccountLocalIdentity(account).storageKey)
            }
        }
        try await localStore.setSyncedIdentityKeys(syncedIdentityKeys, uid: uid)
    }

    func save(_ account: GitProviderAccount) async throws {
        try await localStore.save(account)
        guard let cloudUID else { return }
        if await mirrorToCloud(account, uid: cloudUID) {
            var syncedKeys = localStore.syncedIdentityKeys(uid: cloudUID)
            syncedKeys.insert(GitProviderAccountLocalIdentity(account).storageKey)
            // The account is already durable. A sync bookkeeping failure must not
            // make the caller delete credentials as if the local save had failed.
            try? await localStore.setSyncedIdentityKeys(syncedKeys, uid: cloudUID)
        }
    }

    func delete(accountID: String) async throws {
        guard let deletedAccount = try await localStore.delete(accountID: accountID) else { return }
        guard let cloudUID, let cloudStore else { return }

        let cloudAccountID = cloudAccountIDsByLocalAccountID.removeValue(forKey: accountID) ?? accountID
        do {
            try await cloudStore.delete(accountID: cloudAccountID, macgitUID: cloudUID)
            if cloudAccountID != accountID {
                try? await cloudStore.delete(accountID: accountID, macgitUID: cloudUID)
            }
            try await localStore.clearPendingDeletion(deletedAccount)
            var syncedKeys = localStore.syncedIdentityKeys(uid: cloudUID)
            syncedKeys.remove(GitProviderAccountLocalIdentity(deletedAccount).storageKey)
            try await localStore.setSyncedIdentityKeys(syncedKeys, uid: cloudUID)
        } catch {
            // The local deletion is complete; retry the cloud deletion on the next sync.
        }
    }

    private func mirrorToCloud(_ account: GitProviderAccount, uid: String) async -> Bool {
        guard let cloudStore else { return false }

        var cloudAccount = account
        cloudAccount.macgitUID = uid
        do {
            try await cloudStore.save(cloudAccount)
            if let oldCloudID = cloudAccountIDsByLocalAccountID[account.id],
               oldCloudID != account.id {
                try? await cloudStore.delete(accountID: oldCloudID, macgitUID: uid)
            }
            cloudAccountIDsByLocalAccountID[account.id] = account.id
            return true
        } catch {
            // Local metadata and credentials remain authoritative when cloud sync fails.
            return false
        }
    }
}

private struct GitProviderAccountLocalIdentity: Hashable {
    let provider: GitProviderKind
    let host: String
    let providerUserID: String

    var storageKey: String {
        [provider.rawValue, host, providerUserID].joined(separator: "|")
    }

    init(_ account: GitProviderAccount) {
        provider = account.provider
        host = (account.hostURL.host(percentEncoded: false) ?? account.hostURL.absoluteString).lowercased()
        providerUserID = account.providerUserID
    }
}
