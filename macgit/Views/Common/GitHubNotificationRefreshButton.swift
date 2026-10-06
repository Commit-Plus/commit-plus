// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitHubNotificationRefreshButton: View {
    @ObservedObject var controller: GitHubNotificationController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let next = controller.selectedAccounts.compactMap { account -> Date? in
                guard let cache = controller.caches[controller.key(account)] else { return nil }
                return max(cache.nextFetchAt ?? .distantPast, cache.retryAt ?? .distantPast)
            }.min() ?? .distantPast
            let waiting = next > context.date
            Button("Refresh", systemImage: "arrow.clockwise") { controller.refreshSelected() }
                .labelStyle(.iconOnly)
                .disabled(controller.isRefreshing || controller.accounts.isEmpty || waiting)
                .help(waiting ? "GitHub allows refresh in \(Int(ceil(next.timeIntervalSince(context.date)))) seconds" : "Fetch latest GitHub notifications")
        }
    }
}
