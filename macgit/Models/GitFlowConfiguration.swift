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

struct GitFlowConfiguration: Codable, Equatable {
    static let supportedSchemaVersion = 1

    var roleDisplayMode: GitFlowRoleDisplayMode
    var schemaVersion: Int
    var isEnabled: Bool
    var mainBranch: String
    var developBranch: String
    var featurePrefix: String
    var bugfixPrefix: String
    var releasePrefix: String
    var hotfixPrefix: String
    var defaultStartDestination: GitFlowStartDestination
    var topicFinishStrategy: GitFlowTopicFinishStrategy
    var createReleaseTagOnFinish: Bool
    var deleteLocalBranchOnFinish: Bool
    var removeLocalWorktreeOnFinish: Bool
    var createHotfixTagOnFinish: Bool

    init(
        roleDisplayMode: GitFlowRoleDisplayMode = .full,
        schemaVersion: Int = GitFlowConfiguration.supportedSchemaVersion,
        isEnabled: Bool = false,
        mainBranch: String = "main",
        developBranch: String = "develop",
        featurePrefix: String = "feature/",
        bugfixPrefix: String = "bugfix/",
        releasePrefix: String = "release/",
        hotfixPrefix: String = "hotfix/",
        defaultStartDestination: GitFlowStartDestination = .currentWorkingCopy,
        topicFinishStrategy: GitFlowTopicFinishStrategy = .mergeNoFastForward,
        createReleaseTagOnFinish: Bool = true,
        deleteLocalBranchOnFinish: Bool = true,
        removeLocalWorktreeOnFinish: Bool = false,
        createHotfixTagOnFinish: Bool = true
    ) {
        self.deleteLocalBranchOnFinish = deleteLocalBranchOnFinish
        self.removeLocalWorktreeOnFinish = removeLocalWorktreeOnFinish
        self.roleDisplayMode = roleDisplayMode
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.mainBranch = mainBranch
        self.developBranch = developBranch
        self.featurePrefix = featurePrefix
        self.bugfixPrefix = bugfixPrefix
        self.releasePrefix = releasePrefix
        self.hotfixPrefix = hotfixPrefix
        self.defaultStartDestination = defaultStartDestination
        self.topicFinishStrategy = topicFinishStrategy
        self.createReleaseTagOnFinish = createReleaseTagOnFinish
        self.createHotfixTagOnFinish = createHotfixTagOnFinish
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deleteLocalBranchOnFinish = try container.decodeIfPresent(Bool.self, forKey: .deleteLocalBranchOnFinish) ?? true
        removeLocalWorktreeOnFinish = try container.decodeIfPresent(Bool.self, forKey: .removeLocalWorktreeOnFinish) ?? false
        roleDisplayMode = try container.decodeIfPresent(GitFlowRoleDisplayMode.self, forKey: .roleDisplayMode) ?? .full
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        mainBranch = try container.decodeIfPresent(String.self, forKey: .mainBranch) ?? "main"
        developBranch = try container.decodeIfPresent(String.self, forKey: .developBranch) ?? "develop"
        featurePrefix = try container.decodeIfPresent(String.self, forKey: .featurePrefix) ?? "feature/"
        bugfixPrefix = try container.decodeIfPresent(String.self, forKey: .bugfixPrefix) ?? "bugfix/"
        releasePrefix = try container.decodeIfPresent(String.self, forKey: .releasePrefix) ?? "release/"
        hotfixPrefix = try container.decodeIfPresent(String.self, forKey: .hotfixPrefix) ?? "hotfix/"
        defaultStartDestination = try container.decodeIfPresent(
            GitFlowStartDestination.self,
            forKey: .defaultStartDestination
        ) ?? .currentWorkingCopy
        topicFinishStrategy = try container.decodeIfPresent(
            GitFlowTopicFinishStrategy.self,
            forKey: .topicFinishStrategy
        ) ?? .mergeNoFastForward
        createReleaseTagOnFinish = try container.decodeIfPresent(
            Bool.self,
            forKey: .createReleaseTagOnFinish
        ) ?? true
        createHotfixTagOnFinish = try container.decodeIfPresent(
            Bool.self,
            forKey: .createHotfixTagOnFinish
        ) ?? true
    }

    static func detected(branches: [String]) -> GitFlowConfiguration {
        GitFlowConfiguration(
            mainBranch: branches.contains("main") ? "main" : (branches.contains("master") ? "master" : branches.first ?? "main"),
            developBranch: branches.contains("develop") ? "develop" : "develop"
        )
    }

    func prefix(for kind: GitFlowTopicKind) -> String {
        switch kind {
        case .feature: return featurePrefix
        case .bugfix: return bugfixPrefix
        case .release: return releasePrefix
        case .hotfix: return hotfixPrefix
        }
    }

    func baseBranch(for kind: GitFlowTopicKind) -> String {
        switch kind {
        case .feature, .bugfix, .release:
            return developBranch
        case .hotfix:
            return mainBranch
        }
    }

    func normalized() -> GitFlowConfiguration {
        GitFlowConfiguration(
            roleDisplayMode: roleDisplayMode,
            schemaVersion: Self.supportedSchemaVersion,
            isEnabled: isEnabled,
            mainBranch: mainBranch.trimmingCharacters(in: .whitespacesAndNewlines),
            developBranch: developBranch.trimmingCharacters(in: .whitespacesAndNewlines),
            featurePrefix: Self.normalizedPrefix(featurePrefix),
            bugfixPrefix: Self.normalizedPrefix(bugfixPrefix),
            releasePrefix: Self.normalizedPrefix(releasePrefix),
            hotfixPrefix: Self.normalizedPrefix(hotfixPrefix),
            defaultStartDestination: defaultStartDestination,
            topicFinishStrategy: topicFinishStrategy,
            createReleaseTagOnFinish: createReleaseTagOnFinish,
            deleteLocalBranchOnFinish: deleteLocalBranchOnFinish,
            removeLocalWorktreeOnFinish: removeLocalWorktreeOnFinish,
            createHotfixTagOnFinish: createHotfixTagOnFinish
        )
    }

    private static func normalizedPrefix(_ prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasSuffix("/") ? trimmed : "\(trimmed)/"
    }
}
