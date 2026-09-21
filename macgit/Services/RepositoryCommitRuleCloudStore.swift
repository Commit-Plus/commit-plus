// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FirebaseFirestore

@MainActor
protocol RepositoryCommitRuleCloudStore {
    func load(identity: RepositoryBookmarkIdentity, uid: String) async throws -> Bool?
    func save(_ skipWarnings: Bool, identity: RepositoryBookmarkIdentity, uid: String) async throws
}

@MainActor
final class FirestoreRepositoryCommitRuleStore: RepositoryCommitRuleCloudStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func load(identity: RepositoryBookmarkIdentity, uid: String) async throws -> Bool? {
        let snapshot = try await document(identity: identity, uid: uid).getDocument(source: .server)
        guard snapshot.exists else { return nil }
        guard let data = snapshot.data(),
              data["schemaVersion"] as? Int == 1,
              data["canonicalKey"] as? String == identity.canonicalKey,
              let value = data["skipProtectedBranchCommitWarnings"] as? Bool else {
            throw CloudSettingsError.invalidDocument
        }
        return value
    }

    func save(_ skipWarnings: Bool, identity: RepositoryBookmarkIdentity, uid: String) async throws {
        try await document(identity: identity, uid: uid).setData([
            "schemaVersion": 1,
            "canonicalKey": identity.canonicalKey,
            "skipProtectedBranchCommitWarnings": skipWarnings,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    private func document(identity: RepositoryBookmarkIdentity, uid: String) -> DocumentReference {
        firestore.collection("users").document(uid)
            .collection("repositoryCommitRules").document(identity.documentID)
    }
}
