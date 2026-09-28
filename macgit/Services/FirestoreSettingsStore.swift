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

enum CloudSettingsDocument {
    static func encode(
        _ snapshot: AppSettingsSnapshot,
        updatedAt: Any
    ) -> [String: Any] {
        [
            "schemaVersion": snapshot.schemaVersion,
            "appearance": snapshot.appearance.rawValue,
            "showToolbarButtonText": snapshot.showToolbarButtonText,
            "showGitFlow": snapshot.showGitFlow,
            "showWorkspaceReflog": snapshot.showWorkspaceReflog,
            "showWorkspacePullRequests": snapshot.showWorkspacePullRequests,
            "showWorkspaceGitLFS": snapshot.showWorkspaceGitLFS,
            "showSubmodules": snapshot.showSubmodules,
            "showSubtrees": snapshot.showSubtrees,
            "showHeaderBranchButton": snapshot.showHeaderBranchButton,
            "showHeaderMergeButton": snapshot.showHeaderMergeButton,
            "showHeaderStashButton": snapshot.showHeaderStashButton,
            "showHeaderUndoButton": snapshot.showHeaderUndoButton,
            "showHeaderRemoteButton": snapshot.showHeaderRemoteButton,
            "showHeaderFinderButton": snapshot.showHeaderFinderButton,
            "showHeaderEditorButton": snapshot.showHeaderEditorButton,
            "showHeaderTerminalButton": snapshot.showHeaderTerminalButton,
            "showHeaderSettingsButton": snapshot.showHeaderSettingsButton,
            "historyBranchFilter": snapshot.historyBranchFilter.storageValue,
            "historyIncludeRemotes": snapshot.historyIncludeRemotes,
            "autoFetchEnabled": snapshot.autoFetchEnabled,
            "refreshOnAppActive": snapshot.refreshOnAppActive,
            "updatedAt": updatedAt
        ]
    }

    static func decode(_ data: [String: Any]?) throws -> AppSettingsSnapshot {
        guard let data,
              let schemaVersion = data["schemaVersion"] as? Int,
              schemaVersion == 1,
              let showToolbarButtonText = data["showToolbarButtonText"] as? Bool,
              let showSubmodules = data["showSubmodules"] as? Bool,
              let showSubtrees = data["showSubtrees"] as? Bool,
              data["updatedAt"] is Timestamp else {
            throw CloudSettingsError.invalidDocument
        }

        let appearance: AppAppearance
        if let rawAppearance = data["appearance"] as? String {
            guard let decodedAppearance = AppAppearance(rawValue: rawAppearance) else {
                throw CloudSettingsError.invalidDocument
            }
            appearance = decodedAppearance
        } else if data["appearance"] != nil {
            throw CloudSettingsError.invalidDocument
        } else {
            appearance = .system
        }

        return AppSettingsSnapshot(
            appearance: appearance,
            showToolbarButtonText: showToolbarButtonText,
            showGitFlow: data["showGitFlow"] as? Bool ?? true,
            showWorkspaceReflog: data["showWorkspaceReflog"] as? Bool ?? true,
            showWorkspacePullRequests: data["showWorkspacePullRequests"] as? Bool ?? true,
            showWorkspaceGitLFS: data["showWorkspaceGitLFS"] as? Bool ?? true,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees,
            showHeaderBranchButton: data["showHeaderBranchButton"] as? Bool ?? true,
            showHeaderMergeButton: data["showHeaderMergeButton"] as? Bool ?? true,
            showHeaderStashButton: data["showHeaderStashButton"] as? Bool ?? true,
            showHeaderUndoButton: data["showHeaderUndoButton"] as? Bool ?? false,
            showHeaderRemoteButton: data["showHeaderRemoteButton"] as? Bool ?? true,
            showHeaderFinderButton: data["showHeaderFinderButton"] as? Bool ?? true,
            showHeaderEditorButton: data["showHeaderEditorButton"] as? Bool ?? true,
            showHeaderTerminalButton: data["showHeaderTerminalButton"] as? Bool ?? true,
            showHeaderSettingsButton: data["showHeaderSettingsButton"] as? Bool ?? false,
            historyBranchFilter: (data["historyBranchFilter"] as? String)
                .flatMap(HistoryBranchFilter.init(storageValue:)) ?? .all,
            historyIncludeRemotes: data["historyIncludeRemotes"] as? Bool ?? false,
            autoFetchEnabled: data["autoFetchEnabled"] as? Bool ?? false,
            refreshOnAppActive: data["refreshOnAppActive"] as? Bool ?? true
        )
    }
}

@MainActor
final class FirestoreSettingsStore: CloudSettingsStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func load(uid: String) async throws -> AppSettingsSnapshot? {
        let snapshot = try await document(uid: uid).getDocument()
        guard snapshot.exists else { return nil }
        return try CloudSettingsDocument.decode(snapshot.data(with: .estimate))
    }

    func save(_ snapshot: AppSettingsSnapshot, uid: String) async throws {
        try await document(uid: uid).setData(
            CloudSettingsDocument.encode(snapshot, updatedAt: FieldValue.serverTimestamp())
        )
    }

    func observe(
        uid: String,
        onChange: @escaping (Result<AppSettingsSnapshot, Error>) -> Void
    ) -> ObservationToken {
        let registration = document(uid: uid).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }

            do {
                let value = try CloudSettingsDocument.decode(snapshot?.data(with: .estimate))
                onChange(.success(value))
            } catch {
                onChange(.failure(error))
            }
        }
        return SettingsFirestoreObservationToken(registration: registration)
    }

    private func document(uid: String) -> DocumentReference {
        firestore.collection("users").document(uid).collection("settings").document("app")
    }
}

private final class SettingsFirestoreObservationToken: ObservationToken {
    private var registration: ListenerRegistration?

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit {
        registration?.remove()
    }
}
