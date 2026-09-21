// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum LegacyLocalDataMigration {
    // Leave the original defaults intact for recovery. The database migration
    // marker prevents stale defaults from resurrecting subsequently deleted rows.
    static func records(from defaults: UserDefaults) throws -> [String: [String: Data]] {
        var transaction = LocalDataTransaction(records: [:])
        func decode<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
            guard defaults.object(forKey: key) != nil else { return nil }
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode(type, from: data) else {
                throw LocalDataError.invalidLegacyData(key)
            }
            return value
        }
        func dictionary<T>(_ type: T.Type, key: String) throws -> [String: T] {
            guard defaults.object(forKey: key) != nil else { return [:] }
            guard let values = defaults.dictionary(forKey: key) as? [String: T] else {
                throw LocalDataError.invalidLegacyData(key)
            }
            return values
        }
        func strings(key: String) throws -> [String] {
            guard defaults.object(forKey: key) != nil else { return [] }
            guard let values = defaults.stringArray(forKey: key) else { throw LocalDataError.invalidLegacyData(key) }
            return values
        }
        let prefix = "dev.thanhtran.macgit."
        for bookmark in try decode([RepositoryBookmark].self, key: prefix + "repositoryBookmarks.items") ?? [] {
            try transaction.set(bookmark, in: "bookmarks", id: bookmark.id)
        }
        for (id, path) in try dictionary(String.self, key: prefix + "repositoryBookmarks.localPaths") {
            try transaction.set(path, in: "bookmarkPaths", id: id)
        }
        for id in try strings(key: prefix + "repositoryBookmarks.pendingUploads") {
            try transaction.set(UUID().uuidString, in: "bookmarkUploads", id: id)
        }
        for id in try strings(key: prefix + "repositoryBookmarks.pendingDeletes") {
            try transaction.set(UUID().uuidString, in: "bookmarkDeletes", id: id)
        }
        for account in try decode([GitProviderAccount].self, key: prefix + "localGitProviderAccounts") ?? [] {
            try transaction.set(account, in: "providerAccounts", id: account.id)
        }
        for account in try decode([GitProviderAccount].self, key: prefix + "localGitProviderAccountPendingDeletions") ?? [] {
            try transaction.set(account, in: "providerDeletions", id: account.id)
        }
        for (uid, identities) in try dictionary([String].self, key: prefix + "localGitProviderAccountSyncedIdentities") {
            try transaction.set(identities, in: "providerSyncedIdentities", id: uid)
        }
        for (id, settings) in try decode([String: RepoSettings].self, key: prefix + "repoSettings") ?? [:] {
            try transaction.set(settings, in: "repoSettings", id: id)
        }
        for (id, accountID) in try dictionary(String.self, key: prefix + "providerAccountPreferences") {
            try transaction.set(accountID, in: "providerPreferences", id: id)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("gitProviderSSHKey.") {
            if let value = try decode(GitProviderSSHKey.self, key: key) {
                try transaction.set(value, in: "sshPaths", id: key)
            }
        }
        for (id, value) in try dictionary(Bool.self, key: prefix + "repositoryCommitRules.pending") {
            try transaction.set(value, in: "commitRulePending", id: id)
        }
        for id in try strings(key: prefix + "gitFlowConfiguration.pendingUploads") {
            try transaction.set(UUID().uuidString, in: "gitFlowPending", id: id)
        }
        // This cache is disposable. A corrupt cache must not prevent migration of user data.
        if let values = try? decode([String: CachedRepositoryVisibility].self, key: prefix + "repositoryVisibility") {
            for (id, value) in values where Date().timeIntervalSince(value.resolvedAt) <= 30 * 24 * 60 * 60 {
                try transaction.set(value, in: "repositoryVisibility", id: id)
            }
        }
        return transaction.records
    }
}
