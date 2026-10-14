// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct CommitFileListView: View {
    @Environment(\.appTextScale) private var textScale
    let changes: [CommitFileChange]
    var lineCounts: [String: FileLineChangeCount] = [:]
    @Binding var selectedFile: CommitFileChange?
    var allowsEmptySelection = true
    var showsLayoutControls = false
    var onOpenFile: ((CommitFileChange) -> Void)? = nil
    var onPatch: (([CommitFileChange], CommitPatchRequest.Direction) -> Void)? = nil
    var patchDisabledReason: (([CommitFileChange]) -> String?)? = nil
    @State private var selectedFiles: Set<CommitFileChange> = []

    @ViewBuilder
    var body: some View {
        Group {
            if showsLayoutControls {
                FilePathListView(
                    items: changes,
                    path: \.path
                ) {
                    Text("Files")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(changes.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                } trailing: {
                    EmptyView()
                } plainContent: {
                    nativeList
                } treeContent: { rows, toggleFolder in
                    nativeTreeList(rows: rows, toggleFolder: toggleFolder)
                }
            } else {
                nativeList
            }
        }
        .onAppear { synchronizeSelection() }
        .onChange(of: changes) {
            selectedFiles = selectedFiles.intersection(Set(changes))
            synchronizeSelection()
        }
        .onChange(of: selectedFile) { synchronizeSelection() }
    }

    private var nativeList: some View {
        CommitFileNativeList(
            rows: changes.map { .init(change: $0, count: lineCounts[$0.path]) },
            selectedIDs: Set(selectedFiles.map(\.id)),
            primarySelectedID: selectedFile?.id,
            allowsMultipleSelection: onPatch != nil,
            allowsEmptySelection: allowsEmptySelection,
            textScale: textScale,
            onSelectionChange: updateSelection,
            onOpenFile: onOpenFile,
            makeContextMenu: onPatch == nil ? nil : { change in
                NSHostingMenu(rootView: patchMenu(for: change))
            }
        )
    }

    private func nativeTreeList(
        rows: [FilePathTreeRow<CommitFileChange>],
        toggleFolder: @escaping (String) -> Void
    ) -> some View {
        CommitFileTreeNativeList(
            rows: rows.map { row in
                switch row.content {
                case .folder(let path, let name, _, let expanded):
                    return .init(id: row.id, depth: row.depth, content: .folder(path: path, name: name, isExpanded: expanded))
                case .file(let change, let name):
                    return .init(id: row.id, depth: row.depth, content: .file(change: change, name: name, count: lineCounts[change.path]))
                }
            },
            selectedIDs: Set(selectedFiles.map(\.id)), textScale: textScale,
            onToggleFolder: toggleFolder, onSelect: selectTreeFile, onOpenFile: onOpenFile,
            makeContextMenu: onPatch == nil ? nil : { change in NSHostingMenu(rootView: patchMenu(for: change)) }
        )
    }

    private func updateSelection(_ files: [CommitFileChange], primary: CommitFileChange?) {
        selectedFiles = Set(files)
        if let primary, selectedFiles.contains(primary) {
            selectedFile = primary
        } else {
            selectedFile = files.first
        }
    }

    private func selectTreeFile(_ file: CommitFileChange) {
        guard onPatch != nil else {
            selectedFiles = [file]
            selectedFile = file
            return
        }
        let modifiers = (NSApp.currentEvent?.modifierFlags ?? []).intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift), let anchor = selectedFile,
           let anchorIndex = changes.firstIndex(of: anchor), let index = changes.firstIndex(of: file) {
            selectedFiles = Set(changes[min(anchorIndex, index)...max(anchorIndex, index)])
        } else if modifiers.contains(.command) {
            if selectedFiles.contains(file) { selectedFiles.remove(file) }
            else { selectedFiles.insert(file) }
        } else {
            selectedFiles = [file]
        }
        if selectedFiles.contains(file) { selectedFile = file }
        else { selectedFile = selectedFiles.first }
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
