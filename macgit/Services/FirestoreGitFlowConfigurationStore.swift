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

enum GitFlowCloudConfigurationDocumentError: LocalizedError {
    case invalidDocument

    var errorDescription: String? {
        "The synced Git Flow configuration is malformed."
    }
}

enum GitFlowCloudConfigurationDocument {
    private static let allowedKeys: Set<String> = [
        "roleDisplayMode",
        "schemaVersion",
        "canonicalKey",
        "isEnabled",
        "mainBranch",
        "developBranch",
        "featurePrefix",
        "bugfixPrefix",
        "releasePrefix",
        "hotfixPrefix",
        "topicFinishStrategy",
        "createReleaseTagOnFinish",
        "createHotfixTagOnFinish",
        "updatedAt",
    ]

    static func encode(
        _ configuration: GitFlowCloudConfiguration,
        updatedAt: Any
    ) -> [String: Any] {
        [
            "roleDisplayMode": configuration.roleDisplayMode.rawValue,
            "schemaVersion": GitFlowCloudConfiguration.schemaVersion,
            "canonicalKey": configuration.canonicalKey,
            "isEnabled": configuration.isEnabled,
            "mainBranch": configuration.mainBranch,
            "developBranch": configuration.developBranch,
            "featurePrefix": configuration.featurePrefix,
            "bugfixPrefix": configuration.bugfixPrefix,
            "releasePrefix": configuration.releasePrefix,
            "hotfixPrefix": configuration.hotfixPrefix,
            "topicFinishStrategy": configuration.topicFinishStrategy.rawValue,
            "createReleaseTagOnFinish": configuration.createReleaseTagOnFinish,
            "createHotfixTagOnFinish": configuration.createHotfixTagOnFinish,
            "updatedAt": updatedAt,
        ]
    }

    static func decode(_ data: [String: Any]?) throws -> GitFlowCloudConfiguration {
        guard let data,
              Set(data.keys).isSubset(of: allowedKeys),
              Set(data.keys).isSuperset(of: allowedKeys.subtracting(["roleDisplayMode"])),
              let schemaVersion = data["schemaVersion"] as? Int,
              schemaVersion == GitFlowCloudConfiguration.schemaVersion,
              let canonicalKey = data["canonicalKey"] as? String,
              !canonicalKey.isEmpty,
              let isEnabled = data["isEnabled"] as? Bool,
              let mainBranch = data["mainBranch"] as? String,
              !mainBranch.isEmpty,
              let developBranch = data["developBranch"] as? String,
              !developBranch.isEmpty,
              let featurePrefix = data["featurePrefix"] as? String,
              let bugfixPrefix = data["bugfixPrefix"] as? String,
              let releasePrefix = data["releasePrefix"] as? String,
              let hotfixPrefix = data["hotfixPrefix"] as? String,
              let strategyRawValue = data["topicFinishStrategy"] as? String,
              let topicFinishStrategy = GitFlowTopicFinishStrategy(rawValue: strategyRawValue),
              let createReleaseTagOnFinish = data["createReleaseTagOnFinish"] as? Bool,
              let createHotfixTagOnFinish = data["createHotfixTagOnFinish"] as? Bool,
              data["updatedAt"] is Timestamp else {
            throw GitFlowCloudConfigurationDocumentError.invalidDocument
        }

        let roleDisplayMode: GitFlowRoleDisplayMode
        if let rawValue = data["roleDisplayMode"] {
            guard let value = rawValue as? String, let mode = GitFlowRoleDisplayMode(rawValue: value) else {
                throw GitFlowCloudConfigurationDocumentError.invalidDocument
            }
            roleDisplayMode = mode
        } else {
            roleDisplayMode = .full
        }

        return GitFlowCloudConfiguration(
            canonicalKey: canonicalKey,
            isEnabled: isEnabled,
            mainBranch: mainBranch,
            developBranch: developBranch,
            featurePrefix: featurePrefix,
            bugfixPrefix: bugfixPrefix,
            releasePrefix: releasePrefix,
            hotfixPrefix: hotfixPrefix,
            topicFinishStrategy: topicFinishStrategy,
            createReleaseTagOnFinish: createReleaseTagOnFinish,
            createHotfixTagOnFinish: createHotfixTagOnFinish,
            roleDisplayMode: roleDisplayMode
        )
    }
}

@MainActor
final class FirestoreGitFlowConfigurationStore: GitFlowConfigurationCloudStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func configuration(
        repositoryID: String,
        uid: String
    ) async throws -> GitFlowCloudConfiguration? {
        let snapshot = try await document(repositoryID: repositoryID, uid: uid).getDocument()
        guard snapshot.exists else { return nil }
        return try GitFlowCloudConfigurationDocument.decode(snapshot.data(with: .estimate))
    }

    func save(
        _ configuration: GitFlowCloudConfiguration,
        repositoryID: String,
        uid: String
    ) async throws {
        try await document(repositoryID: repositoryID, uid: uid).setData(
            GitFlowCloudConfigurationDocument.encode(
                configuration,
                updatedAt: FieldValue.serverTimestamp()
            )
        )
    }

    private func document(repositoryID: String, uid: String) -> DocumentReference {
        firestore.collection("users")
            .document(uid)
            .collection("gitFlowConfigurations")
            .document(repositoryID)
    }
}
