// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct LocalDataLoadingView<Content: View>: View {
    @ObservedObject private var store = LocalDataStore.shared
    @State private var retry = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if store.isReady {
                content()
            } else if let message = store.errorMessage {
                ContentUnavailableView {
                    Label("Local Data Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { retry += 1 }
                }
            } else {
                ProgressView("Loading local data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: retry) { try? await store.prepare() }
    }
}
