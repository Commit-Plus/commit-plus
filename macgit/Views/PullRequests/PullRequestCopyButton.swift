// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct PullRequestCopyButton: View {
    let title: String
    let value: String
    var systemImage: String = "doc.on.doc"
    @State private var copyID: UUID?

    var body: some View {
        Button(title, systemImage: copyID == nil ? systemImage : "checkmark") {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(value, forType: .string) {
                copyID = UUID()
            }
        }
        .pointingHandCursor()
        .task(id: copyID) {
            guard copyID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                copyID = nil
            } catch {
                // A new copy restarts the feedback timer; leaving the view cancels it.
            }
        }
        .onChange(of: value) { _, _ in
            copyID = nil
        }
    }
}
