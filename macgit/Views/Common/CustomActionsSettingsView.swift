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
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingsToggleRow(
                        title: "Sync Custom Actions",
                        detail: "Sync scripts and action definitions across your Macs when Settings Sync is enabled. Turn off to stop syncing on this Mac; existing cloud copies remain.",
                        isOn: $store.syncEnabled
                    )
                } footer: {
                    Text("Each Mac must review changed actions before running them.")
                }

                Section {
                    if store.actions.isEmpty {
                        ContentUnavailableView(
                            "No Custom Actions",
                            systemImage: "terminal",
                            description: Text("Add an executable or import a script to get started.")
                        )
                    } else {
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
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Run reusable executables or scripts with repository, file, and commit context.")
                }
            }
            .formStyle(.grouped)

            HStack {
                if let syncError = store.syncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Add…", systemImage: "plus", action: add)
            }
            .padding()
            .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("Custom Actions")
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
