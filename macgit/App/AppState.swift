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
import SwiftUI
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()
    private static let appearanceKey = "appearance"
    private static let textSizeKey = "textSize"
    private static let showToolbarButtonTextKey = "showToolbarButtonText"
    private static let showGitFlowKey = "showGitFlow"
    private static let showWorkspaceReflogKey = "showWorkspaceReflog"
    private static let showWorkspacePullRequestsKey = "showWorkspacePullRequests"
    private static let showWorkspaceGitLFSKey = "showWorkspaceGitLFS"
    private static let showTagsKey = "showTags"
    private static let showWorktreesKey = "showWorktrees"
    private static let showSubmodulesKey = "showSubmodules"
    private static let showSubtreesKey = "showSubtrees"
    private static let showHeaderBranchButtonKey = "showHeaderBranchButton"
    private static let showHeaderMergeButtonKey = "showHeaderMergeButton"
    private static let showHeaderStashButtonKey = "showHeaderStashButton"
    private static let showHeaderUndoButtonKey = "showHeaderUndoButton"
    private static let showHeaderRemoteButtonKey = "showHeaderRemoteButton"
    private static let showHeaderFinderButtonKey = "showHeaderFinderButton"
    private static let showHeaderEditorButtonKey = "showHeaderEditorButton"
    private static let showHeaderTerminalButtonKey = "showHeaderTerminalButton"
    private static let showHeaderSettingsButtonKey = "showHeaderSettingsButton"
    private static let historyBranchFilterKey = "historyBranchFilter"
    private static let historyIncludeRemotesKey = "historyIncludeRemotes"
    private static let autoFetchEnabledKey = "autoFetchEnabled"
    private static let refreshOnAppActiveKey = "refreshOnAppActive"
    private static let fitRepositoryWindowsToScreenKey = "fitRepositoryWindowsToScreen"
    private static let settingsSyncEnabledKey = "settingsSyncEnabled"
    private static let searchFilterKey = "searchFilter"
    private static let preferredSearchFileApplicationKey = "preferredSearchFileApplication"

    private let userDefaults: UserDefaults
    private var isApplyingSnapshot = false
    @Published private var currentSettingsSnapshot: AppSettingsSnapshot =
        AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false)

    @Published var appearance: AppAppearance {
        didSet {
            userDefaults.set(appearance.rawValue, forKey: Self.appearanceKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var textSize: AppTextSize {
        didSet {
            userDefaults.set(textSize.rawValue, forKey: Self.textSizeKey)
        }
    }
    @Published var showToolbarButtonText: Bool {
        didSet {
            userDefaults.set(showToolbarButtonText, forKey: Self.showToolbarButtonTextKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showGitFlow: Bool {
        didSet {
            userDefaults.set(showGitFlow, forKey: Self.showGitFlowKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showWorkspaceReflog: Bool {
        didSet {
            userDefaults.set(showWorkspaceReflog, forKey: Self.showWorkspaceReflogKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showWorkspacePullRequests: Bool {
        didSet {
            userDefaults.set(showWorkspacePullRequests, forKey: Self.showWorkspacePullRequestsKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showWorkspaceGitLFS: Bool {
        didSet {
            userDefaults.set(showWorkspaceGitLFS, forKey: Self.showWorkspaceGitLFSKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showTags: Bool {
        didSet {
            userDefaults.set(showTags, forKey: Self.showTagsKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showWorktrees: Bool {
        didSet {
            userDefaults.set(showWorktrees, forKey: Self.showWorktreesKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showSubmodules: Bool {
        didSet {
            userDefaults.set(showSubmodules, forKey: Self.showSubmodulesKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showSubtrees: Bool {
        didSet {
            userDefaults.set(showSubtrees, forKey: Self.showSubtreesKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderBranchButton: Bool {
        didSet {
            userDefaults.set(showHeaderBranchButton, forKey: Self.showHeaderBranchButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderMergeButton: Bool {
        didSet {
            userDefaults.set(showHeaderMergeButton, forKey: Self.showHeaderMergeButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderStashButton: Bool {
        didSet {
            userDefaults.set(showHeaderStashButton, forKey: Self.showHeaderStashButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published private(set) var showHeaderUndoButton: Bool {
        didSet {
            userDefaults.set(showHeaderUndoButton, forKey: Self.showHeaderUndoButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published private(set) var showHeaderRemoteButton: Bool {
        didSet {
            userDefaults.set(showHeaderRemoteButton, forKey: Self.showHeaderRemoteButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published private(set) var showHeaderFinderButton: Bool {
        didSet {
            userDefaults.set(showHeaderFinderButton, forKey: Self.showHeaderFinderButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published private(set) var showHeaderEditorButton: Bool {
        didSet {
            userDefaults.set(showHeaderEditorButton, forKey: Self.showHeaderEditorButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published private(set) var showHeaderTerminalButton: Bool {
        didSet {
            userDefaults.set(showHeaderTerminalButton, forKey: Self.showHeaderTerminalButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published private(set) var showHeaderSettingsButton: Bool {
        didSet {
            userDefaults.set(showHeaderSettingsButton, forKey: Self.showHeaderSettingsButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var historyBranchFilter: HistoryBranchFilter {
        didSet {
            userDefaults.set(historyBranchFilter.storageValue, forKey: Self.historyBranchFilterKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var historyIncludeRemotes: Bool {
        didSet {
            userDefaults.set(historyIncludeRemotes, forKey: Self.historyIncludeRemotesKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var autoFetchEnabled: Bool {
        didSet {
            userDefaults.set(autoFetchEnabled, forKey: Self.autoFetchEnabledKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var refreshOnAppActive: Bool {
        didSet {
            userDefaults.set(refreshOnAppActive, forKey: Self.refreshOnAppActiveKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var fitRepositoryWindowsToScreen: Bool {
        didSet {
            userDefaults.set(fitRepositoryWindowsToScreen, forKey: Self.fitRepositoryWindowsToScreenKey)
        }
    }
    @Published var syncEnabled: Bool {
        didSet {
            userDefaults.set(syncEnabled, forKey: Self.settingsSyncEnabledKey)
        }
    }
    @Published var searchFilter: SearchFilter {
        didSet {
            userDefaults.set(searchFilter.rawValue, forKey: Self.searchFilterKey)
        }
    }
    @Published var preferredSearchFileApplicationBundleIdentifier: String? {
        didSet {
            if let preferredSearchFileApplicationBundleIdentifier {
                userDefaults.set(
                    preferredSearchFileApplicationBundleIdentifier,
                    forKey: Self.preferredSearchFileApplicationKey
                )
            } else {
                userDefaults.removeObject(forKey: Self.preferredSearchFileApplicationKey)
            }
        }
    }

    var settingsSnapshotPublisher: AnyPublisher<AppSettingsSnapshot, Never> {
        $currentSettingsSnapshot
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let appearance = userDefaults.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        let textSize = userDefaults.string(forKey: Self.textSizeKey)
            .flatMap(AppTextSize.init(rawValue:)) ?? .default
        let showToolbarButtonText = userDefaults.object(forKey: Self.showToolbarButtonTextKey) as? Bool ?? true
        let showGitFlow = userDefaults.object(forKey: Self.showGitFlowKey) as? Bool ?? true
        let showWorkspaceReflog = userDefaults.object(forKey: Self.showWorkspaceReflogKey) as? Bool ?? true
        let showWorkspacePullRequests = userDefaults.object(forKey: Self.showWorkspacePullRequestsKey) as? Bool ?? true
        let showWorkspaceGitLFS = userDefaults.object(forKey: Self.showWorkspaceGitLFSKey) as? Bool ?? true
        let showTags = userDefaults.object(forKey: Self.showTagsKey) as? Bool ?? true
        let showWorktrees = userDefaults.object(forKey: Self.showWorktreesKey) as? Bool ?? true
        let showSubmodules = userDefaults.object(forKey: Self.showSubmodulesKey) as? Bool ?? false
        let showSubtrees = userDefaults.object(forKey: Self.showSubtreesKey) as? Bool ?? false
        let showHeaderBranchButton = userDefaults.object(forKey: Self.showHeaderBranchButtonKey) as? Bool ?? true
        let showHeaderMergeButton = userDefaults.object(forKey: Self.showHeaderMergeButtonKey) as? Bool ?? true
        let showHeaderStashButton = userDefaults.object(forKey: Self.showHeaderStashButtonKey) as? Bool ?? true
        let showHeaderUndoButton = userDefaults.object(forKey: Self.showHeaderUndoButtonKey) as? Bool ?? false
        let showHeaderRemoteButton = userDefaults.object(forKey: Self.showHeaderRemoteButtonKey) as? Bool ?? true
        let showHeaderFinderButton = userDefaults.object(forKey: Self.showHeaderFinderButtonKey) as? Bool ?? true
        let showHeaderEditorButton = userDefaults.object(forKey: Self.showHeaderEditorButtonKey) as? Bool ?? true
        let showHeaderTerminalButton = userDefaults.object(forKey: Self.showHeaderTerminalButtonKey) as? Bool ?? true
        let showHeaderSettingsButton = userDefaults.object(forKey: Self.showHeaderSettingsButtonKey) as? Bool ?? false
        let historyBranchFilter = userDefaults.string(forKey: Self.historyBranchFilterKey)
            .flatMap(HistoryBranchFilter.init(storageValue:)) ?? .all
        let historyIncludeRemotes = userDefaults.object(forKey: Self.historyIncludeRemotesKey) as? Bool ?? false
        let autoFetchEnabled = userDefaults.object(forKey: Self.autoFetchEnabledKey) as? Bool ?? false
        let refreshOnAppActive = userDefaults.object(forKey: Self.refreshOnAppActiveKey) as? Bool ?? true
        let fitRepositoryWindowsToScreen = userDefaults.object(
            forKey: Self.fitRepositoryWindowsToScreenKey
        ) as? Bool ?? false
        let syncEnabled = userDefaults.object(forKey: Self.settingsSyncEnabledKey) as? Bool ?? false
        let searchFilter = userDefaults.string(forKey: Self.searchFilterKey)
            .flatMap(SearchFilter.init(rawValue:)) ?? .all
        let preferredSearchFileApplicationBundleIdentifier = userDefaults.string(
            forKey: Self.preferredSearchFileApplicationKey
        )
        let loadedSnapshot = AppSettingsSnapshot(
            appearance: appearance,
            showToolbarButtonText: showToolbarButtonText,
            showGitFlow: showGitFlow,
            showWorkspaceReflog: showWorkspaceReflog,
            showWorkspacePullRequests: showWorkspacePullRequests,
            showWorkspaceGitLFS: showWorkspaceGitLFS,
            showTags: showTags,
            showWorktrees: showWorktrees,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees,
            showHeaderBranchButton: showHeaderBranchButton,
            showHeaderMergeButton: showHeaderMergeButton,
            showHeaderStashButton: showHeaderStashButton,
            showHeaderUndoButton: showHeaderUndoButton,
            showHeaderRemoteButton: showHeaderRemoteButton,
            showHeaderFinderButton: showHeaderFinderButton,
            showHeaderEditorButton: showHeaderEditorButton,
            showHeaderTerminalButton: showHeaderTerminalButton,
            showHeaderSettingsButton: showHeaderSettingsButton,
            historyBranchFilter: historyBranchFilter,
            historyIncludeRemotes: historyIncludeRemotes,
            autoFetchEnabled: autoFetchEnabled,
            refreshOnAppActive: refreshOnAppActive
        ).normalizedRepositoryToolbarShortcuts()

        self.appearance = appearance
        self.textSize = textSize
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
        self.showHeaderUndoButton = loadedSnapshot.showHeaderUndoButton
        self.showHeaderRemoteButton = loadedSnapshot.showHeaderRemoteButton
        self.showHeaderFinderButton = loadedSnapshot.showHeaderFinderButton
        self.showHeaderEditorButton = loadedSnapshot.showHeaderEditorButton
        self.showHeaderTerminalButton = loadedSnapshot.showHeaderTerminalButton
        self.showHeaderSettingsButton = loadedSnapshot.showHeaderSettingsButton
        self.historyBranchFilter = historyBranchFilter
        self.historyIncludeRemotes = historyIncludeRemotes
        self.autoFetchEnabled = autoFetchEnabled
        self.refreshOnAppActive = refreshOnAppActive
        self.fitRepositoryWindowsToScreen = fitRepositoryWindowsToScreen
        self.syncEnabled = syncEnabled
        self.searchFilter = searchFilter
        self.preferredSearchFileApplicationBundleIdentifier = preferredSearchFileApplicationBundleIdentifier
        currentSettingsSnapshot = loadedSnapshot
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            appearance: appearance,
            showToolbarButtonText: showToolbarButtonText,
            showGitFlow: showGitFlow,
            showWorkspaceReflog: showWorkspaceReflog,
            showWorkspacePullRequests: showWorkspacePullRequests,
            showWorkspaceGitLFS: showWorkspaceGitLFS,
            showTags: showTags,
            showWorktrees: showWorktrees,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees,
            showHeaderBranchButton: showHeaderBranchButton,
            showHeaderMergeButton: showHeaderMergeButton,
            showHeaderStashButton: showHeaderStashButton,
            showHeaderUndoButton: showHeaderUndoButton,
            showHeaderRemoteButton: showHeaderRemoteButton,
            showHeaderFinderButton: showHeaderFinderButton,
            showHeaderEditorButton: showHeaderEditorButton,
            showHeaderTerminalButton: showHeaderTerminalButton,
            showHeaderSettingsButton: showHeaderSettingsButton,
            historyBranchFilter: historyBranchFilter,
            historyIncludeRemotes: historyIncludeRemotes,
            autoFetchEnabled: autoFetchEnabled,
            refreshOnAppActive: refreshOnAppActive
        )
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        let snapshot = snapshot.normalizedRepositoryToolbarShortcuts()
        isApplyingSnapshot = true
        defer { isApplyingSnapshot = false }
        appearance = snapshot.appearance
        showToolbarButtonText = snapshot.showToolbarButtonText
        showGitFlow = snapshot.showGitFlow
        showWorkspaceReflog = snapshot.showWorkspaceReflog
        showWorkspacePullRequests = snapshot.showWorkspacePullRequests
        showWorkspaceGitLFS = snapshot.showWorkspaceGitLFS
        showTags = snapshot.showTags
        showWorktrees = snapshot.showWorktrees
        showSubmodules = snapshot.showSubmodules
        showSubtrees = snapshot.showSubtrees
        showHeaderBranchButton = snapshot.showHeaderBranchButton
        showHeaderMergeButton = snapshot.showHeaderMergeButton
        showHeaderStashButton = snapshot.showHeaderStashButton
        showHeaderUndoButton = snapshot.showHeaderUndoButton
        showHeaderRemoteButton = snapshot.showHeaderRemoteButton
        showHeaderFinderButton = snapshot.showHeaderFinderButton
        showHeaderEditorButton = snapshot.showHeaderEditorButton
        showHeaderTerminalButton = snapshot.showHeaderTerminalButton
        showHeaderSettingsButton = snapshot.showHeaderSettingsButton
        historyBranchFilter = snapshot.historyBranchFilter
        historyIncludeRemotes = snapshot.historyIncludeRemotes
        autoFetchEnabled = snapshot.autoFetchEnabled
        refreshOnAppActive = snapshot.refreshOnAppActive
        currentSettingsSnapshot = snapshot
    }

    var pinnedRepositoryToolbarShortcuts: [RepositoryToolbarShortcut] {
        snapshot.pinnedRepositoryToolbarShortcuts
    }

    @discardableResult
    func setRepositoryToolbarShortcut(
        _ shortcut: RepositoryToolbarShortcut,
        isPinned: Bool
    ) -> Bool {
        if isPinned,
           !isRepositoryToolbarShortcutPinned(shortcut),
           pinnedRepositoryToolbarShortcuts.count >= RepositoryToolbarShortcut.maximumPinnedCount {
            return false
        }

        switch shortcut {
        case .undo: showHeaderUndoButton = isPinned
        case .remote: showHeaderRemoteButton = isPinned
        case .finder: showHeaderFinderButton = isPinned
        case .editor: showHeaderEditorButton = isPinned
        case .terminal: showHeaderTerminalButton = isPinned
        case .settings: showHeaderSettingsButton = isPinned
        }
        return true
    }

    func isRepositoryToolbarShortcutPinned(_ shortcut: RepositoryToolbarShortcut) -> Bool {
        switch shortcut {
        case .undo: showHeaderUndoButton
        case .remote: showHeaderRemoteButton
        case .finder: showHeaderFinderButton
        case .editor: showHeaderEditorButton
        case .terminal: showHeaderTerminalButton
        case .settings: showHeaderSettingsButton
        }
    }

    func restoreLocalOnlyPreferences() {
        searchFilter = .all
        preferredSearchFileApplicationBundleIdentifier = nil
    }
}
