// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

final class DiffNativeCell: NSTableCellView {
    let host = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    override init(frame: NSRect) {
        super.init(frame: frame)
        host.sizingOptions = []
        // Rows have explicit frames. Avoid solving four constraints for every
        // hosting view whenever a native scroll slice moves or changes size.
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
