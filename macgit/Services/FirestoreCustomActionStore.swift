// SPDX-License-Identifier: AGPL-3.0-or-later

import FirebaseFirestore
import Foundation

enum FirestoreCustomActionDocument {
    static func encode(_ action: CustomActionDefinition, updatedAt: Any) -> [String: Any] {
        var data: [String: Any] = [
            "schemaVersion": CustomActionDefinition.schemaVersion,
            "name": action.name,
            "sourceKind": action.sourceKind.rawValue,
            "executablePath": action.executablePath,
            "arguments": action.arguments,
            "availability": action.availability.rawValue,
            "isEnabled": action.isEnabled,
            "alwaysShowOutput": action.alwaysShowOutput,
            "sortIndex": action.sortIndex,
            "updatedAt": updatedAt,
        ]
        if let scriptLanguage = action.scriptLanguage {
            data["scriptLanguage"] = scriptLanguage.rawValue
        }
        if let scriptSource = action.scriptSource {
            data["scriptSource"] = scriptSource
        }
        if let sourceFileName = action.sourceFileName {
            data["sourceFileName"] = sourceFileName
        }
        return data
    }

    static func decode(id: String, data: [String: Any]) throws -> CustomActionDefinition {
        guard let uuid = UUID(uuidString: id),
              data["schemaVersion"] as? Int == CustomActionDefinition.schemaVersion,
              let name = data["name"] as? String,
              let sourceKindRaw = data["sourceKind"] as? String,
              let sourceKind = CustomActionSourceKind(rawValue: sourceKindRaw),
              let executablePath = data["executablePath"] as? String,
              let arguments = data["arguments"] as? [String],
              let availabilityRaw = data["availability"] as? Int,
              let isEnabled = data["isEnabled"] as? Bool,
              let alwaysShowOutput = data["alwaysShowOutput"] as? Bool,
              let sortIndex = data["sortIndex"] as? Int,
              data["updatedAt"] is Timestamp else {
            throw CloudSettingsError.invalidDocument
        }

        let scriptLanguage: CustomActionScriptLanguage?
        if let raw = data["scriptLanguage"] as? String {
            guard let decoded = CustomActionScriptLanguage(rawValue: raw) else {
                throw CloudSettingsError.invalidDocument
            }
            scriptLanguage = decoded
        } else {
            scriptLanguage = nil
        }

        return CustomActionDefinition(
            id: uuid,
            name: name,
            sourceKind: sourceKind,
            executablePath: executablePath,
            scriptLanguage: scriptLanguage,
            scriptSource: data["scriptSource"] as? String,
            sourceFileName: data["sourceFileName"] as? String,
            arguments: arguments,
            availability: CustomActionAvailability(rawValue: availabilityRaw),
            isEnabled: isEnabled,
            alwaysShowOutput: alwaysShowOutput,
            sortIndex: sortIndex
        )
    }
}

@MainActor
final class FirestoreCustomActionStore: CustomActionCloudStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func load(uid: String) async throws -> [CustomActionDefinition] {
        let snapshot = try await collection(uid: uid).getDocuments()
        return try snapshot.documents
            .map { try FirestoreCustomActionDocument.decode(id: $0.documentID, data: $0.data()) }
            .sorted(by: Self.order)
    }

    func upsert(_ action: CustomActionDefinition, uid: String) async throws {
        try await collection(uid: uid).document(action.id.uuidString).setData(
            FirestoreCustomActionDocument.encode(action, updatedAt: FieldValue.serverTimestamp())
        )
    }

    func delete(id: UUID, uid: String) async throws {
        try await collection(uid: uid).document(id.uuidString).delete()
    }

    func updateOrder(_ actions: [CustomActionDefinition], uid: String) async throws {
        let batch = firestore.batch()
        for action in actions {
            batch.updateData(
                ["sortIndex": action.sortIndex, "updatedAt": FieldValue.serverTimestamp()],
                forDocument: collection(uid: uid).document(action.id.uuidString)
            )
        }
        try await batch.commit()
    }

    func observe(
        uid: String,
        onChange: @escaping (Result<[CustomActionDefinition], Error>) -> Void
    ) -> ObservationToken {
        let registration = collection(uid: uid).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }
            do {
                let actions = try (snapshot?.documents ?? [])
                    .map { try FirestoreCustomActionDocument.decode(id: $0.documentID, data: $0.data()) }
                    .sorted(by: Self.order)
                onChange(.success(actions))
            } catch {
                onChange(.failure(error))
            }
        }
        return CustomActionFirestoreObservationToken(registration: registration)
    }

    private func collection(uid: String) -> CollectionReference {
        firestore.collection("users").document(uid).collection("customActions")
    }

    private static func order(_ lhs: CustomActionDefinition, _ rhs: CustomActionDefinition) -> Bool {
        if lhs.sortIndex == rhs.sortIndex { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
        return lhs.sortIndex < rhs.sortIndex
    }
}

private final class CustomActionFirestoreObservationToken: ObservationToken {
    private var registration: ListenerRegistration?

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit { registration?.remove() }
}
