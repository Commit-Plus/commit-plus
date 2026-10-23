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

import FirebaseFirestore
import Foundation

enum GitProviderAccountDocumentError: LocalizedError {
    case invalidDocument

    var errorDescription: String? {
        "Git provider account metadata is malformed."
    }
}

enum GitProviderAccountDocument {
    static func encode(_ account: GitProviderAccount) -> [String: Any] {
        var data: [String: Any] = [
            "schemaVersion": 1,
            "provider": account.provider.rawValue,
            "hostURL": account.hostURL.absoluteString,
            "providerUserID": account.providerUserID,
            "username": account.username,
            "scopes": account.scopes,
            "permissions": account.permissions,
            "tokenStatus": account.tokenStatus.rawValue,
            "transportProtocol": account.transportProtocol.rawValue,
            "connectedAt": Timestamp(date: account.connectedAt)
        ]
        if let displayName = account.displayName {
            data["displayName"] = displayName
        }
        if let avatarURL = account.avatarURL {
            data["avatarURL"] = avatarURL.absoluteString
        }
        if let lastValidatedAt = account.lastValidatedAt {
            data["lastValidatedAt"] = Timestamp(date: lastValidatedAt)
        }
        return data
    }

    /// Skips accounts for providers added by a newer app version instead of failing the whole list.
    static func decodeSupported(
        _ documents: [(id: String, data: [String: Any])],
        macgitUID: String
    ) throws -> [GitProviderAccount] {
        try documents.compactMap { document in
            if let provider = document.data["provider"] as? String, GitProviderKind(rawValue: provider) == nil {
                return nil
            }
            return try decode(document.data, id: document.id, macgitUID: macgitUID)
        }
    }

    static func decode(
        _ data: [String: Any],
        id: String,
        macgitUID: String
    ) throws -> GitProviderAccount {
        guard let schemaVersion = data["schemaVersion"] as? Int,
              schemaVersion == 1,
              let providerRaw = data["provider"] as? String,
              let provider = GitProviderKind(rawValue: providerRaw),
              let hostRaw = data["hostURL"] as? String,
              let hostURL = URL(string: hostRaw),
              let providerUserID = data["providerUserID"] as? String,
              let username = data["username"] as? String,
              let scopes = data["scopes"] as? [String],
              let permissions = data["permissions"] as? [String: String],
              let tokenStatusRaw = data["tokenStatus"] as? String,
              let tokenStatus = GitProviderTokenStatus(rawValue: tokenStatusRaw),
              let connectedAt = (data["connectedAt"] as? Timestamp)?.dateValue() else {
            throw GitProviderAccountDocumentError.invalidDocument
        }

        let avatarURL: URL?
        if let avatarRaw = data["avatarURL"] as? String {
            guard let parsedURL = URL(string: avatarRaw) else {
                throw GitProviderAccountDocumentError.invalidDocument
            }
            avatarURL = parsedURL
        } else {
            avatarURL = nil
        }

        let transportProtocol = (data["transportProtocol"] as? String)
            .flatMap(GitProviderTransportProtocol.init(rawValue:)) ?? .https

        return GitProviderAccount(
            id: id,
            macgitUID: macgitUID,
            provider: provider,
            hostURL: hostURL,
            providerUserID: providerUserID,
            username: username,
            displayName: data["displayName"] as? String,
            avatarURL: avatarURL,
            scopes: scopes,
            permissions: permissions,
            tokenStatus: tokenStatus,
            transportProtocol: transportProtocol,
            connectedAt: connectedAt,
            lastValidatedAt: (data["lastValidatedAt"] as? Timestamp)?.dateValue()
        )
    }
}

@MainActor
final class FirestoreGitProviderAccountStore: GitProviderAccountCloudStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func accounts(forMacgitUID uid: String) async throws -> [GitProviderAccount] {
        let snapshot = try await collection(uid: uid).getDocuments()
        return try GitProviderAccountDocument.decodeSupported(
            snapshot.documents.map { (id: $0.documentID, data: $0.data()) },
            macgitUID: uid
        )
    }

    func save(_ account: GitProviderAccount) async throws {
        try await collection(uid: account.macgitUID)
            .document(account.id)
            .setData(GitProviderAccountDocument.encode(account))
    }

    func delete(accountID: String, macgitUID: String) async throws {
        try await collection(uid: macgitUID).document(accountID).delete()
    }

    private func collection(uid: String) -> CollectionReference {
        firestore.collection("users").document(uid).collection("gitProviderAccounts")
    }
}
