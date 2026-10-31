//
//  ToolbarAction.swift
//  macgit
//

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

enum ToolbarAction: Hashable {
    case commit, pull, push, fetch, addSubmodule, addLinkSubtree, branch, merge, stash
    case tag, createPullRequest, refresh
    case remote, finder, editor, terminal, repositorySettings, search
}

struct ToolbarActionState: Equatable {
    let isSyncing: Bool
    let stagedCount: Int
    let stashableCount: Int
}

extension Notification.Name {
    static let toolbarAction = Notification.Name("macgit.toolbarAction")
}

struct ToolbarActionKey: FocusedValueKey {
    typealias Value = Binding<ToolbarAction>
}

struct ToolbarActionStateKey: FocusedValueKey {
    typealias Value = ToolbarActionState
}

extension FocusedValues {
    var toolbarAction: Binding<ToolbarAction>? {
        get { self[ToolbarActionKey.self] }
        set { self[ToolbarActionKey.self] = newValue }
    }

    var toolbarActionState: ToolbarActionState? {
        get { self[ToolbarActionStateKey.self] }
        set { self[ToolbarActionStateKey.self] = newValue }
    }
}
