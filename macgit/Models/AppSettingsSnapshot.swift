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

struct AppSettingsSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var appearance: AppAppearance
    var showToolbarButtonText: Bool
    var showGitFlow: Bool
    var showWorkspaceReflog: Bool
    var showWorkspacePullRequests: Bool
    var showWorkspaceGitLFS: Bool
    var showTags: Bool
    var showWorktrees: Bool
    var showSubmodules: Bool
    var showSubtrees: Bool
    var showHeaderBranchButton: Bool
    var showHeaderMergeButton: Bool
    var showHeaderStashButton: Bool
    var showHeaderUndoButton: Bool
    var showHeaderRemoteButton: Bool
    var showHeaderFinderButton: Bool
    var showHeaderEditorButton: Bool
    var showHeaderTerminalButton: Bool
    var showHeaderSettingsButton: Bool
    var historyBranchFilter: HistoryBranchFilter
    var historyIncludeRemotes: Bool
    var autoFetchEnabled: Bool
    var refreshOnAppActive: Bool

    init(
        appearance: AppAppearance = .system,
        showToolbarButtonText: Bool,
        showGitFlow: Bool = true,
        showWorkspaceReflog: Bool = true,
        showWorkspacePullRequests: Bool = true,
        showWorkspaceGitLFS: Bool = true,
        showTags: Bool = true,
        showWorktrees: Bool = true,
        showSubmodules: Bool,
        showSubtrees: Bool,
        showHeaderBranchButton: Bool = true,
        showHeaderMergeButton: Bool = true,
        showHeaderStashButton: Bool = true,
        showHeaderUndoButton: Bool = false,
        showHeaderRemoteButton: Bool = true,
        showHeaderFinderButton: Bool = true,
        showHeaderEditorButton: Bool = true,
        showHeaderTerminalButton: Bool = true,
        showHeaderSettingsButton: Bool = false,
        historyBranchFilter: HistoryBranchFilter = .all,
        historyIncludeRemotes: Bool = false,
        autoFetchEnabled: Bool = false,
        refreshOnAppActive: Bool = true
    ) {
        schemaVersion = 1
        self.appearance = appearance
        self.showToolbarButtonText = showToolbarButtonText
        self.showGitFlow = showGitFlow
        self.showWorkspaceReflog = showWorkspaceReflog
        self.showWorkspacePullRequests = showWorkspacePullRequests
        self.showWorkspaceGitLFS = showWorkspaceGitLFS
        self.showTags = showTags
        self.showWorktrees = showWorktrees
        self.showSubmodules = showSubmodules
        self.showSubtrees = showSubtrees
        self.showHeaderBranchButton = showHeaderBranchButton
        self.showHeaderMergeButton = showHeaderMergeButton
        self.showHeaderStashButton = showHeaderStashButton
        self.showHeaderUndoButton = showHeaderUndoButton
        self.showHeaderRemoteButton = showHeaderRemoteButton
        self.showHeaderFinderButton = showHeaderFinderButton
        self.showHeaderEditorButton = showHeaderEditorButton
        self.showHeaderTerminalButton = showHeaderTerminalButton
        self.showHeaderSettingsButton = showHeaderSettingsButton
        self.historyBranchFilter = historyBranchFilter
        self.historyIncludeRemotes = historyIncludeRemotes
        self.autoFetchEnabled = autoFetchEnabled
        self.refreshOnAppActive = refreshOnAppActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        appearance = try container.decode(AppAppearance.self, forKey: .appearance)
        showToolbarButtonText = try container.decode(Bool.self, forKey: .showToolbarButtonText)
        showGitFlow = try container.decodeIfPresent(Bool.self, forKey: .showGitFlow) ?? true
        showWorkspaceReflog = try container.decodeIfPresent(Bool.self, forKey: .showWorkspaceReflog) ?? true
        showWorkspacePullRequests = try container.decodeIfPresent(Bool.self, forKey: .showWorkspacePullRequests) ?? true
        showWorkspaceGitLFS = try container.decodeIfPresent(Bool.self, forKey: .showWorkspaceGitLFS) ?? true
        showTags = try container.decodeIfPresent(Bool.self, forKey: .showTags) ?? true
        showWorktrees = try container.decodeIfPresent(Bool.self, forKey: .showWorktrees) ?? true
        showSubmodules = try container.decode(Bool.self, forKey: .showSubmodules)
        showSubtrees = try container.decode(Bool.self, forKey: .showSubtrees)
        showHeaderBranchButton = try container.decode(Bool.self, forKey: .showHeaderBranchButton)
        showHeaderMergeButton = try container.decode(Bool.self, forKey: .showHeaderMergeButton)
        showHeaderStashButton = try container.decode(Bool.self, forKey: .showHeaderStashButton)
        showHeaderUndoButton = try container.decodeIfPresent(Bool.self, forKey: .showHeaderUndoButton) ?? false
        showHeaderRemoteButton = try container.decode(Bool.self, forKey: .showHeaderRemoteButton)
        showHeaderFinderButton = try container.decode(Bool.self, forKey: .showHeaderFinderButton)
        showHeaderEditorButton = try container.decode(Bool.self, forKey: .showHeaderEditorButton)
        showHeaderTerminalButton = try container.decode(Bool.self, forKey: .showHeaderTerminalButton)
        showHeaderSettingsButton = try container.decodeIfPresent(Bool.self, forKey: .showHeaderSettingsButton) ?? false
        historyBranchFilter = try container.decode(HistoryBranchFilter.self, forKey: .historyBranchFilter)
        historyIncludeRemotes = try container.decode(Bool.self, forKey: .historyIncludeRemotes)
        autoFetchEnabled = try container.decode(Bool.self, forKey: .autoFetchEnabled)
        refreshOnAppActive = try container.decode(Bool.self, forKey: .refreshOnAppActive)
    }
}
