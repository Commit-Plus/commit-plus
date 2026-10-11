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

struct GitFlowCloudConfiguration: Equatable {
    static let schemaVersion = 1

    var canonicalKey: String
    var isEnabled: Bool
    var mainBranch: String
    var developBranch: String
    var featurePrefix: String
    var bugfixPrefix: String
    var releasePrefix: String
    var hotfixPrefix: String
    var topicFinishStrategy: GitFlowTopicFinishStrategy
    var createReleaseTagOnFinish: Bool
    var createHotfixTagOnFinish: Bool

    init(configuration: GitFlowConfiguration, canonicalKey: String) {
        let normalized = configuration.normalized()
        self.canonicalKey = canonicalKey
        isEnabled = normalized.isEnabled
        mainBranch = normalized.mainBranch
        developBranch = normalized.developBranch
        featurePrefix = normalized.featurePrefix
        bugfixPrefix = normalized.bugfixPrefix
        releasePrefix = normalized.releasePrefix
        hotfixPrefix = normalized.hotfixPrefix
        topicFinishStrategy = normalized.topicFinishStrategy
        createReleaseTagOnFinish = normalized.createReleaseTagOnFinish
        createHotfixTagOnFinish = normalized.createHotfixTagOnFinish
    }

    init(
        canonicalKey: String,
        isEnabled: Bool,
        mainBranch: String,
        developBranch: String,
        featurePrefix: String,
        bugfixPrefix: String,
        releasePrefix: String,
        hotfixPrefix: String,
        topicFinishStrategy: GitFlowTopicFinishStrategy,
        createReleaseTagOnFinish: Bool,
        createHotfixTagOnFinish: Bool
    ) {
        self.canonicalKey = canonicalKey
        self.isEnabled = isEnabled
        self.mainBranch = mainBranch
        self.developBranch = developBranch
        self.featurePrefix = featurePrefix
        self.bugfixPrefix = bugfixPrefix
        self.releasePrefix = releasePrefix
        self.hotfixPrefix = hotfixPrefix
        self.topicFinishStrategy = topicFinishStrategy
        self.createReleaseTagOnFinish = createReleaseTagOnFinish
        self.createHotfixTagOnFinish = createHotfixTagOnFinish
    }

    func applying(to localConfiguration: GitFlowConfiguration) -> GitFlowConfiguration {
        GitFlowConfiguration(
            isEnabled: isEnabled,
            mainBranch: mainBranch,
            developBranch: developBranch,
            featurePrefix: featurePrefix,
            bugfixPrefix: bugfixPrefix,
            releasePrefix: releasePrefix,
            hotfixPrefix: hotfixPrefix,
            defaultStartDestination: localConfiguration.defaultStartDestination,
            topicFinishStrategy: topicFinishStrategy,
            createReleaseTagOnFinish: createReleaseTagOnFinish,
            deleteLocalBranchOnFinish: localConfiguration.deleteLocalBranchOnFinish,
            removeLocalWorktreeOnFinish: localConfiguration.removeLocalWorktreeOnFinish,
            createHotfixTagOnFinish: createHotfixTagOnFinish
        ).normalized()
    }
}
