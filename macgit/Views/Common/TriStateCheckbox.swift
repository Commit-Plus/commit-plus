//
//  TriStateCheckbox.swift
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
import AppKit
import SwiftUI

struct TriStateCheckbox: NSViewRepresentable {
    let state: NSControl.StateValue
    let accessibilityLabel: String
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.setButtonType(.switch)
        button.allowsMixedState = true
        button.title = ""
        button.isBordered = false
        button.controlSize = .small
        button.state = state
        button.setAccessibilityLabel(accessibilityLabel)
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 18)
        ])
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.state = state
        button.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.currentState = state
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onChange: onChange)
    }

    final class Coordinator: NSObject {
        var currentState: NSControl.StateValue
        var onChange: ((Bool) -> Void)?

        init(state: NSControl.StateValue, onChange: @escaping (Bool) -> Void) {
            self.currentState = state
            self.onChange = onChange
        }

        @objc func clicked(_ button: NSButton) {
            let selectAll = currentState != .on
            // The owner's state is the source of truth; undo AppKit's own toggle
            // so a failed or ignored change does not leave a stale checkmark.
            button.state = currentState
            onChange?(selectAll)
        }
    }
}
