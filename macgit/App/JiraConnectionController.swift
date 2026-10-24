// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Owns the single Jira Cloud connection for the signed-in Commit+ account on this Mac.
@MainActor
final class JiraConnectionController: ObservableObject {
    @Published private(set) var connection: JiraConnection?
    @Published private(set) var isWorking = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?
    private(set) var macgitUID: String?

    let client: JiraIssueServing
    private let tokenStore: JiraTokenStoring
    private let connectionStore: JiraConnectionPersisting

    init(
        client: JiraIssueServing = JiraCloudClient(),
        tokenStore: JiraTokenStoring = KeychainJiraTokenStore(),
        connectionStore: JiraConnectionPersisting = LocalJiraConnectionStore()
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.connectionStore = connectionStore
    }

    var isSignedIn: Bool { macgitUID != nil }

    func updateMacgitAccount(uid: String?) async {
        guard uid != macgitUID || !hasLoaded else { return }
        macgitUID = uid
        connection = nil
        errorMessage = nil
        guard let uid else {
            hasLoaded = true
            return
        }
        let stored = try? await connectionStore.connection(for: uid)
        guard macgitUID == uid else { return }
        connection = stored
        hasLoaded = true
    }

    /// The saved credential, or nil when nothing is connected or the token is missing from the Keychain.
    func credential() -> JiraCredential? {
        guard let connection, let token = try? tokenStore.token(for: connection), !token.isEmpty else {
            return nil
        }
        return JiraCredential(email: connection.email, token: token)
    }

    @discardableResult
    func connect(site: String, email: String, token: String) async -> Bool {
        guard let uid = macgitUID else {
            errorMessage = JiraError.notSignedIn.localizedDescription
            return false
        }
        guard connection == nil else {
            errorMessage = "Remove the connected Jira site before connecting another one."
            return false
        }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !token.isEmpty else {
            errorMessage = "Enter your Atlassian account email and API token."
            return false
        }

        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let siteURL = try JiraSiteNormalizer.normalize(site)
            let credential = JiraCredential(email: email, token: token)
            let account = try await client.validate(siteURL: siteURL, credential: credential)
            var connection = JiraConnection(
                macgitUID: uid,
                siteURL: siteURL,
                email: account.email,
                accountID: account.accountID,
                displayName: account.displayName,
                apiBase: account.apiBase
            )
            connection.sprintFieldID = try await discoverSprintField(connection: connection, credential: credential)
            guard macgitUID == uid else { return false }
            try persist(connection, token: token)
            try await saveMetadata(connection)
            self.connection = connection
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Verifies a new token for the same site and account before replacing the saved one.
    @discardableResult
    func reconnect(token: String) async -> Bool {
        guard let current = connection else {
            errorMessage = JiraError.notConnected.localizedDescription
            return false
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Enter a new Jira API token."
            return false
        }

        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let credential = JiraCredential(email: current.email, token: token)
            let account = try await client.validate(siteURL: current.siteURL, credential: credential)
            guard account.accountID == current.accountID else {
                errorMessage = "This API token belongs to a different Jira account. Remove the connection to switch accounts."
                return false
            }
            var updated = current
            updated.apiBase = account.apiBase
            updated.displayName = account.displayName
            updated.needsReconnect = false
            updated.sprintFieldID = try await discoverSprintField(connection: updated, credential: credential)
                ?? current.sprintFieldID
            guard connection?.id == current.id else { return false }
            let previousToken = try? tokenStore.token(for: current)
            try persist(updated, token: token)
            do {
                try await connectionStore.save(updated)
            } catch {
                if let previousToken { try? tokenStore.saveToken(previousToken, for: current) }
                throw JiraError.storage("Commit+ could not save the Jira connection on this Mac.")
            }
            connection = updated
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    func remove() async {
        guard let current = connection else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try tokenStore.deleteToken(for: current)
            try await connectionStore.removeConnection(for: current.macgitUID)
            connection = nil
            errorMessage = nil
        } catch {
            errorMessage = "Commit+ could not remove the Jira connection: \(error.localizedDescription)"
        }
    }

    /// Called when Jira rejects the saved token during normal use.
    func markNeedsReconnect() async {
        guard var current = connection, !current.needsReconnect else { return }
        current.needsReconnect = true
        connection = current
        try? await connectionStore.save(current)
    }

    private func discoverSprintField(connection: JiraConnection, credential: JiraCredential) async throws -> String? {
        do {
            return try await client.sprintFieldID(baseURL: connection.apiBaseURL, credential: credential)
        } catch JiraError.forbidden, JiraError.invalidResponse {
            // Without field access the list still works; only sprint filtering is unavailable.
            return nil
        }
    }

    private func persist(_ connection: JiraConnection, token: String) throws {
        do {
            try tokenStore.saveToken(token, for: connection)
        } catch {
            throw JiraError.storage("Commit+ could not save the Jira API token in the Keychain.")
        }
    }

    private func saveMetadata(_ connection: JiraConnection) async throws {
        do {
            try await connectionStore.save(connection)
        } catch {
            try? tokenStore.deleteToken(for: connection)
            throw JiraError.storage("Commit+ could not save the Jira connection on this Mac.")
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? JiraError { return error.localizedDescription }
        return JiraError.unreachable.localizedDescription
    }
}
