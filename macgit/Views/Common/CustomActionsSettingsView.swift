// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct CustomActionsSettingsView: View {
    @ObservedObject var store: CustomActionStore
    @State private var selection: UUID?
    @State private var editingAction: CustomActionDefinition?
    @State private var isPresentingEditor = false

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
                    List(selection: $selection) {
                        ForEach(store.actions) { action in
                            CustomActionSettingsRow(
                                action: action,
                                effectiveAction: store.effectiveAction(action),
                                isTrusted: store.isTrusted(action),
                                onToggle: { store.setEnabled($0, for: action) },
                                onReview: { edit(action) },
                                onLocate: { locate(action) }
                            )
                            .tag(action.id)
                            .onTapGesture(count: 2) { edit(action) }
                        }
                        .onMove(perform: store.move)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Add", systemImage: "plus", action: add)
                Button("Remove", systemImage: "minus", action: remove)
                    .disabled(selectedAction == nil)
                Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
                    .disabled(selectedAction == nil)
                Button("Edit…", action: editSelected)
                    .disabled(selectedAction == nil)
                Spacer()
                if let syncError = store.syncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $isPresentingEditor) {
            CustomActionEditorSheet(action: editingAction) { action in
                store.upsert(action)
                selection = action.id
            }
        }
    }

    private var selectedAction: CustomActionDefinition? {
        guard let selection else { return nil }
        return store.actions.first { $0.id == selection }
    }

    private func add() {
        editingAction = nil
        isPresentingEditor = true
    }

    private func edit(_ action: CustomActionDefinition) {
        editingAction = action
        isPresentingEditor = true
    }

    private func editSelected() {
        guard let selectedAction else { return }
        edit(selectedAction)
    }

    private func remove() {
        guard let selectedAction else { return }
        store.delete(selectedAction)
        selection = nil
    }

    private func duplicate() {
        guard let selectedAction else { return }
        store.duplicate(selectedAction)
    }

    private func locate(_ action: CustomActionDefinition) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setExecutableOverride(url.path, for: action)
        store.trust(action)
    }
}
