// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Security

/// The ChatGPT sign-in tokens. Stored only in this Mac's Keychain.
struct ChatGPTTokenSet: Codable, Equatable, Sendable {
    var clientID: String
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var expiresAt: Date
    var scopes: [String]
    var email: String?
    var accountID: String?
    /// The ChatGPT plan type from the Codex ID token, for example "free" or "plus".
    var planType: String?
}

/// Non-secret registration kept across disconnects, so later sign-ins reuse the
/// issued client ID and this Mac's host identifier.
struct ChatGPTRegistration: Codable, Equatable, Sendable {
    var hostID: String
    var clientID: String?
    var email: String?
}

protocol ChatGPTCredentialStoring: Sendable {
    func loadTokens() throws -> ChatGPTTokenSet?
    func saveTokens(_ tokens: ChatGPTTokenSet) throws
    func deleteTokens() throws
    func loadRegistration() throws -> ChatGPTRegistration?
    func saveRegistration(_ registration: ChatGPTRegistration) throws
}

struct KeychainChatGPTCredentialStore: ChatGPTCredentialStoring {
    private let service = "com.commitplus.macgit.ai-provider-accounts"
    private let tokensAccount: String
    private let registrationAccount: String

    /// `accountPrefix` keeps each sign-in flow's Keychain items separate.
    init(accountPrefix: String = "chatgpt") {
        tokensAccount = "\(accountPrefix).tokens"
        registrationAccount = "\(accountPrefix).registration"
    }

    static let codex = Self(accountPrefix: "chatgpt-codex")

    func loadTokens() throws -> ChatGPTTokenSet? {
        try load(ChatGPTTokenSet.self, account: tokensAccount)
    }

    func saveTokens(_ tokens: ChatGPTTokenSet) throws {
        try save(tokens, account: tokensAccount)
    }

    func deleteTokens() throws {
        let status = SecItemDelete(query(account: tokensAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIProviderCredentialStoreError(status: status)
        }
    }

    func loadRegistration() throws -> ChatGPTRegistration? {
        try load(ChatGPTRegistration.self, account: registrationAccount)
    }

    func saveRegistration(_ registration: ChatGPTRegistration) throws {
        try save(registration, account: registrationAccount)
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func load<Value: Decodable>(_ type: Value.Type, account: String) throws -> Value? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AIProviderCredentialStoreError(status: status) }
        guard let data = item as? Data else { throw AIProviderCredentialStoreError(status: errSecDecode) }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, account: String) throws {
        let data = try JSONEncoder().encode(value)
        var item = query(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                query(account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else { throw AIProviderCredentialStoreError(status: updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw AIProviderCredentialStoreError(status: status) }
    }
}
