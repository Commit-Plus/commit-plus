// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Keep the selected commit emphasized while its window is active, even when
/// the Sidebar owns keyboard focus.
final class HistoryCommitRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { super.isEmphasized }
        set { super.isEmphasized = window?.isKeyWindow == true }
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected && isEmphasized ? .emphasized : super.interiorBackgroundStyle
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isEmphasized = window?.isKeyWindow == true
    }
}
