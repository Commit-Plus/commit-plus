// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct CreateTagAtReferenceSheet: View {
    let startPoint: TagStartPoint
    @Binding var name: String
    let onCancel: () -> Void
    let onCreate: @MainActor (String) async throws -> Void
    let onCompleted: () -> Void
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Tag").font(.title2).bold()
            TextField("Enter tag name…", text: $name).textFieldStyle(.roundedBorder)
                .disabled(isCreating)
            Text(startPoint.isBranch
                ? "Starting branch: \(startPoint.message)"
                : "Create tag from commit: \(startPoint.message) - \(startPoint.shortHash)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction).disabled(isCreating)
                Spacer()
                if isCreating { ProgressView().controlSize(.small) }
                Button("Create Tag") {
                    guard !isCreating else { return }
                    let tagName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !tagName.isEmpty, !tagName.hasPrefix("-") else {
                        errorMessage = "Enter a tag name that does not begin with a hyphen."
                        return
                    }
                    isCreating = true
                    errorMessage = nil
                    Task {
                        defer { isCreating = false }
                        do { try await onCreate(tagName); onCompleted() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(minWidth: 360, idealWidth: 420)
        .interactiveDismissDisabled(isCreating)
    }
}
