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
import Security

protocol GitProviderTokenVault {
    func readToken(for account: GitProviderAccount) throws -> GitProviderToken?
    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws
    func deleteToken(for account: GitProviderAccount) throws
}

enum GitProviderTokenVaultKey {
    static func key(for account: GitProviderAccount) -> String {
        let host = GitProviderHost.identityKey(account.hostURL)
        return [
            account.macgitUID,
            account.provider.rawValue,
            host.lowercased(),
            account.providerUserID,
        ].joined(separator: ":")
    }
}

struct GitProviderTokenVaultError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}

final class KeychainGitProviderTokenVault: GitProviderTokenVault {
    private let service = "com.commitplus.macgit.git-provider-tokens"
    private static let cacheLock = NSLock()
    private static var tokenCache: [String: GitProviderToken] = [:]
    private static var missingTokenCache: Set<String> = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        let cacheKey = GitProviderTokenVaultKey.key(for: account)
        if let cachedToken = cachedToken(for: cacheKey) {
            return cachedToken
        }
        if isKnownMissing(cacheKey) {
            return nil
        }

        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            cacheMissingToken(for: cacheKey)
            return nil
        }
        guard status == errSecSuccess else {
            throw GitProviderTokenVaultError(status: status)
        }
        guard let data = item as? Data else {
            throw GitProviderTokenVaultError(status: errSecDecode)
        }
        let token = try decoder.decode(GitProviderToken.self, from: data)
        cacheToken(token, for: cacheKey)
        return token
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {
        let data = try encoder.encode(token)
        var item = baseQuery(for: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updates = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(
                baseQuery(for: account) as CFDictionary,
                updates as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw GitProviderTokenVaultError(status: updateStatus)
            }
            cacheToken(token, for: GitProviderTokenVaultKey.key(for: account))
            return
        }
        guard status == errSecSuccess else {
            throw GitProviderTokenVaultError(status: status)
        }
        cacheToken(token, for: GitProviderTokenVaultKey.key(for: account))
    }

    func deleteToken(for account: GitProviderAccount) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitProviderTokenVaultError(status: status)
        }
        cacheMissingToken(for: GitProviderTokenVaultKey.key(for: account))
    }

    private func baseQuery(for account: GitProviderAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: GitProviderTokenVaultKey.key(for: account),
        ]
    }

    private func cachedToken(for key: String) -> GitProviderToken? {
        Self.cacheLock.withLock {
            Self.tokenCache[key]
        }
    }

    private func isKnownMissing(_ key: String) -> Bool {
        Self.cacheLock.withLock {
            Self.missingTokenCache.contains(key)
        }
    }

    private func cacheToken(_ token: GitProviderToken, for key: String) {
        Self.cacheLock.withLock {
            Self.tokenCache[key] = token
            Self.missingTokenCache.remove(key)
        }
    }

    private func cacheMissingToken(for key: String) {
        Self.cacheLock.withLock {
            Self.tokenCache.removeValue(forKey: key)
            Self.missingTokenCache.insert(key)
        }
    }
}
