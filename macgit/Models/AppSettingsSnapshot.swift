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

enum FileListMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case list
    case tree

    var id: Self { self }

    var title: String {
        switch self {
        case .list: "Plain list"
        case .tree: "Tree"
        }
    }
}

struct AppSettingsSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var appearance: AppAppearance
    var showToolbarButtonText: Bool
    var showGitFlow: Bool
    var showWorkspaceReflog: Bool
    var showWorkspacePullRequests: Bool
    var showWorkspaceGitLFS: Bool
    var showWorkspaceJira: Bool
    var showTags: Bool
    var showWorktrees: Bool
    var showSubmodules: Bool
    var showSubtrees: Bool
    var showHeaderBranchButton: Bool
    var showHeaderMergeButton: Bool
    var showHeaderStashButton: Bool
    var showHeaderTagButton: Bool
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
    var fileListMode: FileListMode
    var diffFontName: String
    var diffFontSize: Double
    var diffAddedBackgroundColor: String
    var diffAddedTextColor: String
    var diffRemovedBackgroundColor: String
    var diffRemovedTextColor: String
    var diffSyntaxHighlighting: Bool

    init(
        appearance: AppAppearance = .system,
        showToolbarButtonText: Bool,
        showGitFlow: Bool = true,
        showWorkspaceReflog: Bool = true,
        showWorkspacePullRequests: Bool = true,
        showWorkspaceGitLFS: Bool = true,
        showWorkspaceJira: Bool = true,
        showTags: Bool = true,
        showWorktrees: Bool = true,
        showSubmodules: Bool,
        showSubtrees: Bool,
        showHeaderBranchButton: Bool = true,
        showHeaderMergeButton: Bool = true,
        showHeaderStashButton: Bool = true,
        showHeaderTagButton: Bool = true,
        showHeaderUndoButton: Bool = false,
        showHeaderRemoteButton: Bool = true,
        showHeaderFinderButton: Bool = true,
        showHeaderEditorButton: Bool = true,
        showHeaderTerminalButton: Bool = true,
        showHeaderSettingsButton: Bool = false,
        historyBranchFilter: HistoryBranchFilter = .all,
        historyIncludeRemotes: Bool = false,
        autoFetchEnabled: Bool = false,
        refreshOnAppActive: Bool = true,
        fileListMode: FileListMode = .list,
        diffFontName: String = "Menlo-Regular",
        diffFontSize: Double = 12,
        diffAddedBackgroundColor: String = "#00A6661F",
        diffAddedTextColor: String = "#006E4FFF",
        diffRemovedBackgroundColor: String = "#E6331F1F",
        diffRemovedTextColor: String = "#C72E0DFF",
        diffSyntaxHighlighting: Bool = false
    ) {
        schemaVersion = 1
        self.appearance = appearance
        self.showToolbarButtonText = showToolbarButtonText
        self.showGitFlow = showGitFlow
        self.showWorkspaceReflog = showWorkspaceReflog
        self.showWorkspacePullRequests = showWorkspacePullRequests
        self.showWorkspaceGitLFS = showWorkspaceGitLFS
        self.showWorkspaceJira = showWorkspaceJira
        self.showTags = showTags
        self.showWorktrees = showWorktrees
        self.showSubmodules = showSubmodules
        self.showSubtrees = showSubtrees
        self.showHeaderBranchButton = showHeaderBranchButton
        self.showHeaderMergeButton = showHeaderMergeButton
        self.showHeaderStashButton = showHeaderStashButton
        self.showHeaderTagButton = showHeaderTagButton
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
        self.fileListMode = fileListMode
        self.diffFontName = diffFontName
        self.diffFontSize = diffFontSize
        self.diffAddedBackgroundColor = diffAddedBackgroundColor
        self.diffAddedTextColor = diffAddedTextColor
        self.diffRemovedBackgroundColor = diffRemovedBackgroundColor
        self.diffRemovedTextColor = diffRemovedTextColor
        self.diffSyntaxHighlighting = diffSyntaxHighlighting
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
        showWorkspaceJira = try container.decodeIfPresent(Bool.self, forKey: .showWorkspaceJira) ?? true
        showTags = try container.decodeIfPresent(Bool.self, forKey: .showTags) ?? true
        showWorktrees = try container.decodeIfPresent(Bool.self, forKey: .showWorktrees) ?? true
        showSubmodules = try container.decode(Bool.self, forKey: .showSubmodules)
        showSubtrees = try container.decode(Bool.self, forKey: .showSubtrees)
        showHeaderBranchButton = try container.decode(Bool.self, forKey: .showHeaderBranchButton)
        showHeaderMergeButton = try container.decode(Bool.self, forKey: .showHeaderMergeButton)
        showHeaderStashButton = try container.decode(Bool.self, forKey: .showHeaderStashButton)
        showHeaderTagButton = try container.decodeIfPresent(Bool.self, forKey: .showHeaderTagButton) ?? true
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
        fileListMode = try container.decodeIfPresent(FileListMode.self, forKey: .fileListMode) ?? .list
        diffFontName = try container.decodeIfPresent(String.self, forKey: .diffFontName) ?? "Menlo-Regular"
        diffFontSize = try container.decodeIfPresent(Double.self, forKey: .diffFontSize) ?? 12
        diffAddedBackgroundColor = try container.decodeIfPresent(
            String.self, forKey: .diffAddedBackgroundColor
        ) ?? "#00A6661F"
        diffAddedTextColor = try container.decodeIfPresent(
            String.self, forKey: .diffAddedTextColor
        ) ?? "#006E4FFF"
        diffRemovedBackgroundColor = try container.decodeIfPresent(
            String.self, forKey: .diffRemovedBackgroundColor
        ) ?? "#E6331F1F"
        diffRemovedTextColor = try container.decodeIfPresent(
            String.self, forKey: .diffRemovedTextColor
        ) ?? "#C72E0DFF"
        diffSyntaxHighlighting = try container.decodeIfPresent(
            Bool.self, forKey: .diffSyntaxHighlighting
        ) ?? false
    }
}
