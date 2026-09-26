// SPDX-License-Identifier: AGPL-3.0-or-later
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
