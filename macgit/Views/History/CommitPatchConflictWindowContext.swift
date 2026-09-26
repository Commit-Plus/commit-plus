//
//  CommitPatchConflictWindowContext.swift
//  macgit
//
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software; you can redistribute it and/or modify
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

/// Routes Cmd-Z inside the temporary resolver to editor/resolution undo, never repository undo.
struct CommitPatchConflictWindowContext: NSViewRepresentable {
    let identifier: NSUserInterfaceItemIdentifier

    func makeNSView(context: Context) -> ContextView {
        let view = ContextView()
        view.contextIdentifier = identifier
        return view
    }

    func updateNSView(_ view: ContextView, context: Context) {}

    final class ContextView: NSView {
        var contextIdentifier: NSUserInterfaceItemIdentifier?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let contextIdentifier { window?.identifier = contextIdentifier }
        }
    }
}
