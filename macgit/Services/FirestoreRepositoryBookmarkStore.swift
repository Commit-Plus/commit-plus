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

enum RepositoryBookmarkDocumentError: LocalizedError {
    case invalidDocument

    var errorDescription: String? {
        "Repository bookmark metadata is malformed."
    }
}

enum RepositoryBookmarkDocument {
    static func encode(_ bookmark: RepositoryBookmark) -> [String: Any] {
        [
            "schemaVersion": RepositoryBookmark.schemaVersion,
            "canonicalKey": bookmark.canonicalKey,
            "name": bookmark.name,
            "provider": bookmark.provider.rawValue,
            "host": bookmark.host,
            "ownerPath": bookmark.ownerPath,
            "remoteURL": bookmark.remoteURL.absoluteString,
            "createdAt": Timestamp(date: bookmark.createdAt),
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }

    static func decode(_ data: [String: Any], id: String) throws -> RepositoryBookmark {
        guard let schemaVersion = data["schemaVersion"] as? Int,
              schemaVersion == RepositoryBookmark.schemaVersion,
              let canonicalKey = data["canonicalKey"] as? String,
              let name = data["name"] as? String,
              let providerRaw = data["provider"] as? String,
              let provider = RepositoryBookmarkProvider(rawValue: providerRaw),
              let host = data["host"] as? String,
              let ownerPath = data["ownerPath"] as? String,
              let remoteURLRaw = data["remoteURL"] as? String,
              let remoteURL = URL(string: remoteURLRaw),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
              !canonicalKey.isEmpty,
              !name.isEmpty,
              !host.isEmpty,
              !ownerPath.isEmpty else {
            throw RepositoryBookmarkDocumentError.invalidDocument
        }

        return RepositoryBookmark(
            id: id,
            canonicalKey: canonicalKey,
            name: name,
            provider: provider,
            host: host,
            ownerPath: ownerPath,
            remoteURL: remoteURL,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@MainActor
final class FirestoreRepositoryBookmarkStore: RepositoryBookmarkCloudStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func bookmarks(uid: String) async throws -> [RepositoryBookmark] {
        let snapshot = try await collection(uid: uid).getDocuments()
        return try snapshot.documents.map {
            try RepositoryBookmarkDocument.decode(
                $0.data(with: .estimate),
                id: $0.documentID
            )
        }
    }

    func save(_ bookmark: RepositoryBookmark, uid: String) async throws {
        try await collection(uid: uid)
            .document(bookmark.id)
            .setData(RepositoryBookmarkDocument.encode(bookmark))
    }

    func delete(bookmarkID: String, uid: String) async throws {
        try await collection(uid: uid).document(bookmarkID).delete()
    }

    private func collection(uid: String) -> CollectionReference {
        firestore.collection("users").document(uid).collection("repositoryBookmarks")
    }
}
