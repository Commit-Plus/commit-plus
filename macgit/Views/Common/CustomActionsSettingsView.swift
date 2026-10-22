// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct CustomActionsSettingsView: View {
    @ObservedObject var store: CustomActionStore
    @State private var editor: EditorPresentation?
    @State private var selectedActionID: CustomActionDefinition.ID?
    @State private var removingAction: CustomActionDefinition?

    private struct EditorPresentation: Identifiable {
        let id = UUID()
        let action: CustomActionDefinition?
    }

    private var selectedAction: CustomActionDefinition? {
        store.actions.first { $0.id == selectedActionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.syncEnabled) {
                Text("Sync custom actions across your Macs")
                Text("Syncs scripts and action definitions when Settings Sync is enabled. Turning this off stops syncing on this Mac; existing cloud copies remain. Each Mac must review changed actions before running them.")
            }

            HStack(spacing: 16) {
                actionList
                    .frame(width: Self.listWidth)

                detailPanel
            }
            .frame(maxHeight: .infinity)

            HStack {
                ControlGroup {
                    Button("Add Action", systemImage: "plus", action: add)
                        .help("Add a custom action")

                    Button("Remove Action", systemImage: "minus") {
                        removingAction = selectedAction
                    }
                    .disabled(selectedAction == nil)
                    .help("Remove the selected action")
                }
                .labelStyle(.iconOnly)
                .fixedSize()

                Spacer()

                if let selectedAction {
                    let status = CustomActionStatus(
                        action: selectedAction,
                        effectiveAction: store.effectiveAction(selectedAction),
                        isTrusted: store.isTrusted(selectedAction)
                    )
                    Label(status.title, systemImage: status.systemImage)
                        .foregroundStyle(status.color)
                }
            }

            if let syncError = store.syncError {
                Text(syncError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Custom Actions")
        .onChange(of: store.actions.map(\.id), initial: true) { _, ids in
            if let selectedActionID, ids.contains(selectedActionID) { return }
            selectedActionID = ids.first
        }
        .alert(
            "Remove Custom Action?",
            isPresented: Binding(
                get: { removingAction != nil },
                set: { if !$0 { removingAction = nil } }
            ),
            presenting: removingAction
        ) { action in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                store.delete(action)
            }
        } message: { action in
            Text("“\(action.name)” will be removed from Commit+. The script or executable on disk will not be deleted.")
        }
        .sheet(item: $editor) { presentation in
            CustomActionEditorSheet(action: presentation.action) { action in
                store.saveEditedAction(action, original: presentation.action)
            }
        }
    }

    private static let listWidth: CGFloat = 240

    private var actionList: some View {
        List(selection: $selectedActionID) {
            ForEach(store.actions) { action in
                CustomActionSettingsRow(
                    action: action,
                    effectiveAction: store.effectiveAction(action),
                    isTrusted: store.isTrusted(action)
                )
                .tag(action.id)
            }
            .onMove(perform: store.move)
        }
        .settingsTableStyle()
        .contextMenu(forSelectionType: CustomActionDefinition.ID.self) { ids in
            if let action = action(for: ids) {
                Button("Edit…") { edit(action) }
                Button("Duplicate") { store.duplicate(action) }
                if action.sourceKind != .syncedScript {
                    Button("Locate Executable…") { locate(action) }
                }
                Divider()
                Button("Remove…", role: .destructive) { removingAction = action }
            }
        } primaryAction: { ids in
            if let action = action(for: ids) { edit(action) }
        }
        .onDeleteCommand {
            removingAction = selectedAction
        }
        .overlay {
            if store.actions.isEmpty {
                ContentUnavailableView(
                    "No Custom Actions",
                    systemImage: "terminal",
                    description: Text("Add an executable or import a script to get started.")
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var detailPanel: some View {
        Group {
            if let selectedAction {
                CustomActionDetailView(
                    action: selectedAction,
                    effectiveAction: store.effectiveAction(selectedAction),
                    isTrusted: store.isTrusted(selectedAction),
                    onEdit: { edit(selectedAction) },
                    onDuplicate: { store.duplicate(selectedAction) },
                    onLocate: { locate(selectedAction) }
                )
            } else {
                ContentUnavailableView(
                    "No Action Selected",
                    systemImage: "terminal",
                    description: Text("Select an action to preview its script, or add a new one.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailPanelStyle()
    }

    private func action(for ids: Set<CustomActionDefinition.ID>) -> CustomActionDefinition? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return store.actions.first { $0.id == id }
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
