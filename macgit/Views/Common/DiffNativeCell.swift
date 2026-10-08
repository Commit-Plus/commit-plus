// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

final class DiffNativeCell: NSTableCellView {
    let host = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    override init(frame: NSRect) {
        super.init(frame: frame)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
