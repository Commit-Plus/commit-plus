// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Keep the selected commit emphasized while its window is active, even when
/// the Sidebar owns keyboard focus.
final class HistoryCommitRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { window?.isKeyWindow == true }
        set { super.isEmphasized = newValue }
    }
}
