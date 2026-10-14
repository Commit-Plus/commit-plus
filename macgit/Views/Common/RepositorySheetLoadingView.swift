// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// The presentation owns preparation: dismissal cancels it and discards late results.
struct RepositorySheetLoadingView<Value, Content: View>: View {
    let title: String
    let load: @MainActor () async throws -> Value
    let onCancel: () -> Void
    var cancelRequestID: UUID? = nil
    @ViewBuilder let content: (Value) -> Content
    @State private var value: Value?
    @State private var errorMessage: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let value {
                content(value)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title).font(.title2).bold()
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).textSelection(.enabled)
                    } else {
                        ProgressView("Loading…")
                    }
                    HStack {
                        Button("Cancel", role: .cancel, action: onCancel)
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        if errorMessage != nil {
                            Button("Retry") { attempt += 1 }
                        }
                    }
                }
                .padding(24)
                .frame(minWidth: 480, minHeight: 180)
            }
        }
        .task(id: attempt) {
            guard value == nil else { return }
            errorMessage = nil
            do {
                let result = try await load()
                try Task.checkCancellation()
                value = result
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: cancelRequestID) { _, _ in
            if value == nil { onCancel() }
        }
    }
}
