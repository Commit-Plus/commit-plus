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

enum RepositoryToolbarShortcut: String, CaseIterable, Identifiable, Sendable {
    case remote
    case finder
    case editor
    case terminal

    static let maximumPinnedCount = 2

    var id: Self { self }

    var title: String {
        switch self {
        case .remote: "Remote"
        case .finder: "Finder"
        case .editor: "Editor"
        case .terminal: "Terminal"
        }
    }

    var systemImage: String {
        switch self {
        case .remote: "network"
        case .finder: "folder"
        case .editor: "chevron.left.forwardslash.chevron.right"
        case .terminal: "terminal"
        }
    }
}

extension AppSettingsSnapshot {
    var pinnedRepositoryToolbarShortcuts: [RepositoryToolbarShortcut] {
        RepositoryToolbarShortcut.allCases.filter(isRepositoryToolbarShortcutPinned)
    }

    func normalizedRepositoryToolbarShortcuts() -> AppSettingsSnapshot {
        let retained = Set(
            pinnedRepositoryToolbarShortcuts.prefix(RepositoryToolbarShortcut.maximumPinnedCount)
        )
        var normalized = self
        for shortcut in RepositoryToolbarShortcut.allCases {
            normalized.setRepositoryToolbarShortcut(shortcut, isPinned: retained.contains(shortcut))
        }
        return normalized
    }

    func isRepositoryToolbarShortcutPinned(_ shortcut: RepositoryToolbarShortcut) -> Bool {
        switch shortcut {
        case .remote: showHeaderRemoteButton
        case .finder: showHeaderFinderButton
        case .editor: showHeaderEditorButton
        case .terminal: showHeaderTerminalButton
        }
    }

    mutating func setRepositoryToolbarShortcut(
        _ shortcut: RepositoryToolbarShortcut,
        isPinned: Bool
    ) {
        switch shortcut {
        case .remote: showHeaderRemoteButton = isPinned
        case .finder: showHeaderFinderButton = isPinned
        case .editor: showHeaderEditorButton = isPinned
        case .terminal: showHeaderTerminalButton = isPinned
        }
    }
}
