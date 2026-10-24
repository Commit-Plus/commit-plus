// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Stacks repository announcement banners at the top of the detail pane.
/// Items beyond `maxVisible` stay queued and appear as visible banners are closed.
struct RepositoryBannerStack<Item: Identifiable, Banner: View>: View {
    static var maxVisible: Int { 5 }

    let items: [Item]
    @ViewBuilder let banner: (Item) -> Banner

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.prefix(Self.maxVisible)) { item in
                banner(item)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: items.prefix(Self.maxVisible).map(\.id))
    }
}
