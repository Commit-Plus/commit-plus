// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct CustomActionsSettingsView: View {
    @ObservedObject var store: CustomActionStore
    @State private var editor: EditorPresentation?

    private struct EditorPresentation: Identifiable {
        let id = UUID()
        let action: CustomActionDefinition?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Actions")
                    .font(.title2.bold())
                Text("Run reusable executables or scripts with repository, file, and commit context.")
                    .foregroundStyle(.secondary)
                Text("When Settings Sync is enabled, action definitions—including script source and local paths—sync through your Firebase account. Each Mac must review changed actions before running them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                if store.actions.isEmpty {
                    ContentUnavailableView(
                        "No Custom Actions",
                        systemImage: "terminal",
                        description: Text("Add an executable or import a script to get started.")
                    )
                } else {
                    List {
                        ForEach(store.actions) { action in
                            CustomActionSettingsRow(
                                action: action,
                                effectiveAction: store.effectiveAction(action),
                                isTrusted: store.isTrusted(action),
                                onRemove: { store.delete(action) },
                                onDuplicate: { store.duplicate(action) },
                                onEdit: { edit(action) },
                                onReview: { edit(action) },
                                onLocate: { locate(action) }
                            )
                        }
                        .onMove(perform: store.move)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Add", systemImage: "plus", action: add)
                Spacer()
                if let syncError = store.syncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .sheet(item: $editor) { presentation in
            CustomActionEditorSheet(action: presentation.action) { action in
                store.saveEditedAction(action, original: presentation.action)
            }
        }
    }

    private func add() {
        editor = EditorPresentation(action: nil)
    }

    private func edit(_ action: CustomActionDefinition) {
        guard let current = store.action(id: action.id) else { return }
        editor = EditorPresentation(action: current)
    }

    private func locate(_ action: CustomActionDefinition) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setExecutableOverride(url.path, for: action)
    }
}
