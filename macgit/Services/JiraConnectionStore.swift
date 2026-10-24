// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Security

protocol JiraTokenStoring {
    func token(for connection: JiraConnection) throws -> String?
    func saveToken(_ token: String, for connection: JiraConnection) throws
    func deleteToken(for connection: JiraConnection) throws
}

/// Jira API tokens, kept on this Mac only and scoped to the Commit+ account through `JiraConnection.id`.
final class KeychainJiraTokenStore: JiraTokenStoring {
    private let service = "com.commitplus.macgit.jira-tokens"
    private static let cacheLock = NSLock()
    private static var tokenCache: [String: String] = [:]

    func token(for connection: JiraConnection) throws -> String? {
        if let cached = Self.cacheLock.withLock({ Self.tokenCache[connection.id] }) {
            return cached
        }
        var query = baseQuery(for: connection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GitProviderTokenVaultError(status: status) }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw GitProviderTokenVaultError(status: errSecDecode)
        }
        Self.cacheLock.withLock { Self.tokenCache[connection.id] = token }
        return token
    }

    func saveToken(_ token: String, for connection: JiraConnection) throws {
        let data = Data(token.utf8)
        var item = baseQuery(for: connection)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(
                baseQuery(for: connection) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        }
        guard status == errSecSuccess else { throw GitProviderTokenVaultError(status: status) }
        Self.cacheLock.withLock { Self.tokenCache[connection.id] = token }
    }

    func deleteToken(for connection: JiraConnection) throws {
        let status = SecItemDelete(baseQuery(for: connection) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitProviderTokenVaultError(status: status)
        }
        Self.cacheLock.withLock { _ = Self.tokenCache.removeValue(forKey: connection.id) }
    }

    private func baseQuery(for connection: JiraConnection) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.id,
        ]
    }
}

protocol JiraConnectionPersisting {
    func connection(for macgitUID: String) async throws -> JiraConnection?
    func save(_ connection: JiraConnection) async throws
    func removeConnection(for macgitUID: String) async throws
}

/// Connection metadata in local SQLite, one per Commit+ account. Never synced.
final class LocalJiraConnectionStore: JiraConnectionPersisting {
    static let collection = "jiraConnections"
    private let dataStore: LocalDataStore

    init(dataStore: LocalDataStore? = nil) {
        self.dataStore = dataStore ?? .shared
    }

    func connection(for macgitUID: String) async throws -> JiraConnection? {
        try await dataStore.readValue(JiraConnection.self, in: Self.collection, id: macgitUID)
    }

    func save(_ connection: JiraConnection) async throws {
        try await dataStore.transaction { transaction in
            try transaction.set(connection, in: Self.collection, id: connection.macgitUID)
        }
    }

    func removeConnection(for macgitUID: String) async throws {
        try await dataStore.transaction { transaction in
            transaction.remove(in: Self.collection, id: macgitUID)
        }
    }
}
