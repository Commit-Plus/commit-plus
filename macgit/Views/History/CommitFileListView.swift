// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct CommitFileListView: View {
    @Environment(\.appTextScale) private var textScale
    let changes: [CommitFileChange]
    var lineCounts: [String: FileLineChangeCount] = [:]
    @Binding var selectedFile: CommitFileChange?
    var onOpenFile: ((CommitFileChange) -> Void)? = nil
    var onPatch: (([CommitFileChange], CommitPatchRequest.Direction) -> Void)? = nil
    var patchDisabledReason: (([CommitFileChange]) -> String?)? = nil
    @State private var selectedFiles: Set<CommitFileChange> = []

    var body: some View {
        CommitFileNativeList(
            rows: changes.map { .init(change: $0, count: lineCounts[$0.path]) },
            selectedIDs: Set(selectedFiles.map(\.id)),
            primarySelectedID: selectedFile?.id,
            allowsMultipleSelection: onPatch != nil,
            textScale: textScale,
            onSelectionChange: updateSelection,
            onOpenFile: onOpenFile,
            makeContextMenu: onPatch == nil ? nil : { change in
                NSHostingMenu(rootView: patchMenu(for: change))
            }
        )
        .onAppear { synchronizeSelection() }
        .onChange(of: changes) {
            selectedFiles = selectedFiles.intersection(Set(changes))
            synchronizeSelection()
        }
        .onChange(of: selectedFile) { synchronizeSelection() }
    }

    private func updateSelection(_ files: [CommitFileChange], primary: CommitFileChange?) {
        selectedFiles = Set(files)
        if let primary, selectedFiles.contains(primary) {
            selectedFile = primary
        } else {
            selectedFile = files.first
        }
    }

    private func synchronizeSelection() {
        if let selectedFile, changes.contains(selectedFile) {
            if onPatch == nil || !selectedFiles.contains(selectedFile) {
                selectedFiles = [selectedFile]
            }
        } else {
            selectedFiles = []
            if selectedFile != nil { selectedFile = nil }
        }
    }

    @ViewBuilder
    private func patchMenu(for change: CommitFileChange) -> some View {
        let files = selectedFiles.contains(change) ? changes.filter { selectedFiles.contains($0) } : [change]
        let reason = patchDisabledReason?(files)
        Button("Apply Selected Changes") { onPatch?(files, .apply) }
            .disabled(reason != nil)
        Button("Revert Selected Changes") { onPatch?(files, .revert) }
            .disabled(reason != nil)
        if let reason { Text(reason) }
    }
}
