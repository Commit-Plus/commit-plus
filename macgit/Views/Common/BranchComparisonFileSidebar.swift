// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct BranchComparisonFileSidebar: View {
    let controller: ReferenceComparisonController
    @State private var filter = ""
    @State private var tree: [Node] = []
    @State private var collapsedFolders: Set<String> = []
    @State private var visibleRows: [VisibleRow] = []
    @State private var allFolderPaths: Set<String> = []
    @State private var filteredFileCount = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @FocusState private var isFilterFocused: Bool

    private struct Node: Identifiable {
        let id: String
        let name: String
        var file: CommitFileChange?
        var children: [Node] = []
    }

    private struct VisibleRow: Identifiable {
        let node: Node
        let depth: Int
        var id: String { node.id }
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
                        setAllFoldersExpanded(true)
                    }
                    .help("Expand all folders")
                    Button("Collapse all folders", systemImage: "arrow.down.right.and.arrow.up.left") {
                        setAllFoldersExpanded(false)
                    }
                    .help("Collapse all folders")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleRows) { row in
                        TreeRow(node: row.node, controller: controller,
                                isExpanded: !collapsedFolders.contains(row.id)) {
                            toggleFolder(row.id)
                        }
                        .padding(.leading, CGFloat(row.depth) * 14)
                        .frame(height: 30)
                        .id(row.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .scrollPosition($scrollPosition)
            .overlay {
                if visibleRows.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
            Divider()
            HStack {
                Text("\(controller.files.count) changed files")
                Spacer()
                if !filter.isEmpty { Text("\(filteredFileCount) shown") }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(12)
        }
        .background(.background.secondary)
        .onAppear(perform: rebuildTree)
        .onChange(of: controller.files) { rebuildTree(); scrollPosition.scrollTo(edge: .top) }
        .onChange(of: filter) { rebuildTree(); scrollPosition.scrollTo(edge: .top) }
    }

    private var filteredFiles: [CommitFileChange] {
        controller.files.filter { filter.isEmpty || $0.path.localizedStandardContains(filter)
            || ($0.oldPath?.localizedStandardContains(filter) ?? false) }
    }

    private func rebuildTree() {
        let files = filteredFiles
        filteredFileCount = files.count
        tree = nodes(for: files, prefix: "")
        allFolderPaths = Set(controller.files.flatMap { file in
            let parts = file.path.split(separator: "/")
            return (1..<max(1, parts.count)).map { parts.prefix($0).joined(separator: "/") }
        })
        rebuildVisibleRows()
        if controller.selectedFile == nil, filter.isEmpty,
           let firstFile = firstFile(in: tree) {
            controller.selectFile(firstFile)
        }
    }

    private func rebuildVisibleRows() {
        var rows: [VisibleRow] = []
        func append(_ nodes: [Node], depth: Int) {
            for node in nodes {
                rows.append(VisibleRow(node: node, depth: depth))
                if node.file == nil, !collapsedFolders.contains(node.id) {
                    append(node.children, depth: depth + 1)
                }
            }
        }
        append(tree, depth: 0)
        visibleRows = rows
    }

    private func setAllFoldersExpanded(_ expanded: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            collapsedFolders = expanded ? [] : allFolderPaths
            rebuildVisibleRows()
            scrollPosition.scrollTo(edge: .top)
        }
    }

    private func toggleFolder(_ path: String) {
        let collapsing = !collapsedFolders.contains(path)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if collapsing { collapsedFolders.insert(path) }
            else { collapsedFolders.remove(path) }
            rebuildVisibleRows()
            if collapsing { scrollPosition.scrollTo(id: path, anchor: .top) }
        }
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
        let isExpanded: Bool
        let onToggle: () -> Void

        var body: some View {
            if let file = node.file {
                Button {
                    controller.selectFile(file)
                } label: {
                    HStack(spacing: 8) {
                        RevisionTreeIcon(path: file.path, isDirectory: false)
                        Text(node.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let counts = controller.lineCounts[file.path] {
                            HStack(spacing: 4) {
                                Text("+\(counts.added)").foregroundStyle(.green)
                                Text("−\(counts.removed)").foregroundStyle(.red)
                            }
                            .font(.caption.monospacedDigit().weight(.medium))
                            .fixedSize()
                            .accessibilityLabel("\(counts.added) lines added, \(counts.removed) lines removed")
                        }
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
                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 10)
                        RevisionTreeIcon(path: node.id, isDirectory: true, isExpanded: isExpanded)
                        Text(node.name).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(node.name), \(isExpanded ? "expanded" : "collapsed")")
                .help(isExpanded ? "Collapse folder" : "Expand folder")
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
