// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct BranchComparisonFileSidebar: View {
    let controller: ReferenceComparisonController
    @State private var filter = ""
    @State private var tree: [Node] = []
    @State private var collapsedFolders: Set<String> = []
    @FocusState private var isFilterFocused: Bool

    private struct Node: Identifiable {
        let id: String
        let name: String
        var file: CommitFileChange?
        var children: [Node] = []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter files", text: $filter)
                        .textFieldStyle(.plain)
                        .focused($isFilterFocused)
                        .onExitCommand { isFilterFocused = false }
                    if !filter.isEmpty {
                        Button("Clear filter", systemImage: "xmark.circle.fill") { filter = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .background {
                    OutsideClickFocusHandler(isFocused: isFilterFocused) {
                        isFilterFocused = false
                    }
                }
                if !isFilterFocused {
                    Button("Expand all folders", systemImage: "arrow.up.left.and.arrow.down.right") {
                        collapsedFolders.removeAll()
                    }
                    .help("Expand all folders")
                    Button("Collapse all folders", systemImage: "arrow.down.right.and.arrow.up.left") {
                        collapsedFolders = folderPaths(in: nodes(for: controller.files, prefix: ""))
                    }
                    .help("Collapse all folders")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(tree) { node in
                        TreeRow(node: node, controller: controller, collapsedFolders: $collapsedFolders)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .overlay {
                if tree.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
            Divider()
            HStack {
                Text("\(controller.files.count) changed files")
                Spacer()
                if !filter.isEmpty { Text("\(filteredFiles.count) shown") }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(12)
        }
        .background(.background.secondary)
        .onAppear(perform: rebuildTree)
        .onChange(of: controller.files) { rebuildTree() }
        .onChange(of: filter) { rebuildTree() }
    }

    private var filteredFiles: [CommitFileChange] {
        controller.files.filter { filter.isEmpty || $0.path.localizedStandardContains(filter)
            || ($0.oldPath?.localizedStandardContains(filter) ?? false) }
    }

    private func rebuildTree() {
        tree = nodes(for: filteredFiles, prefix: "")
        if controller.selectedFile == nil, filter.isEmpty,
           let firstFile = firstFile(in: tree) {
            controller.selectFile(firstFile)
        }
    }

    private func folderPaths(in nodes: [Node]) -> Set<String> {
        var paths: Set<String> = []
        for node in nodes where node.file == nil {
            paths.insert(node.id)
            paths.formUnion(folderPaths(in: node.children))
        }
        return paths
    }

    private func firstFile(in nodes: [Node]) -> CommitFileChange? {
        for node in nodes {
            if let file = node.file { return file }
            if let file = firstFile(in: node.children) { return file }
        }
        return nil
    }

    private func nodes(for files: [CommitFileChange], prefix: String) -> [Node] {
        let groups = Dictionary(grouping: files) { file in
            String(file.path.dropFirst(prefix.count).split(separator: "/").first ?? "")
        }
        return groups.map { name, files in
            let path = prefix + name
            if let file = files.first(where: { $0.path == path }) {
                return Node(id: path, name: name, file: file)
            }
            return Node(id: path, name: name, children: nodes(for: files, prefix: path + "/"))
        }.sorted {
            if ($0.file == nil) != ($1.file == nil) { return $0.file == nil }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private struct TreeRow: View {
        let node: Node
        let controller: ReferenceComparisonController
        @Binding var collapsedFolders: Set<String>

        private var isExpanded: Bool { !collapsedFolders.contains(node.id) }

        private var expansion: Binding<Bool> {
            Binding(get: { isExpanded }, set: { expanded in
                if expanded { collapsedFolders.remove(node.id) }
                else { collapsedFolders.insert(node.id) }
            })
        }

        var body: some View {
            if let file = node.file {
                Button {
                    controller.selectFile(file)
                } label: {
                    HStack(spacing: 8) {
                        RevisionTreeIcon(path: file.path, isDirectory: false)
                        Text(node.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(statusLetter(file.status))
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(statusColor(file.status))
                            .help(file.status.displayText)
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(controller.selectedFile == file ? Color.accentColor.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(controller.selectedFile == file ? .isSelected : [])
                .help(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)
                .accessibilityLabel("\(file.path), \(file.status.displayText)")
            } else {
                DisclosureGroup(isExpanded: expansion) {
                    ForEach(node.children) { child in
                        TreeRow(node: child, controller: controller, collapsedFolders: $collapsedFolders)
                    }
                    .padding(.leading, 14)
                } label: {
                    HStack(spacing: 8) {
                        RevisionTreeIcon(path: node.id, isDirectory: true, isExpanded: isExpanded)
                        Text(node.name).foregroundStyle(.secondary)
                    }
                        .lineLimit(1)
                        .font(.callout)
                        .padding(.vertical, 5)
                }
                .tint(.secondary)
            }
        }

        private func statusLetter(_ status: CommitFileStatus) -> String {
            switch status {
            case .added: "A"
            case .modified: "M"
            case .deleted: "D"
            case .renamed: "R"
            case .copied: "C"
            }
        }

        private func statusColor(_ status: CommitFileStatus) -> Color {
            switch status {
            case .added: .green
            case .modified: .orange
            case .deleted: .red
            case .renamed: .blue
            case .copied: .purple
            }
        }
    }
}
