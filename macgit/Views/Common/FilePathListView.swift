// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct FilePathTreeRow<Item: Identifiable & Hashable>: Identifiable where Item.ID: Hashable {
    enum Content {
        case folder(path: String, name: String, items: [Item], isExpanded: Bool)
        case file(item: Item, name: String)
    }

    let id: String
    let depth: Int
    let content: Content
}

struct FilePathListView<Item: Identifiable & Hashable, Leading: View, Trailing: View,
                        PlainContent: View, TreeContent: View>: View where Item.ID: Hashable {
    let items: [Item]
    let path: (Item) -> String
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let plainContent: PlainContent
    let treeContent: ([FilePathTreeRow<Item>], @escaping (String) -> Void) -> TreeContent

    @EnvironmentObject private var appState: AppState
    @State private var roots: [Node] = []
    @State private var visibleRows: [FilePathTreeRow<Item>] = []
    @State private var folderPaths: Set<String> = []
    @State private var expandedFolders: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                leading
                Spacer(minLength: 4)
                trailing
                if appState.fileListMode == .tree {
                    Button("Expand all folders", systemImage: "arrow.up.left.and.arrow.down.right", action: expandAll)
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Expand all folders")
                    Button("Collapse all folders", systemImage: "arrow.down.right.and.arrow.up.left", action: collapseAll)
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Collapse all folders")
                }
                Button {
                    appState.fileListMode = appState.fileListMode == .list ? .tree : .list
                } label: {
                    Image(systemName: appState.fileListMode == .list ? "list.bullet" : "list.bullet.indent")
                }
                .buttonStyle(.borderless)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .help(appState.fileListMode == .list ? "Switch to tree view" : "Switch to plain list")
                .accessibilityLabel(appState.fileListMode == .list ? "Switch to tree view" : "Switch to plain list")
            }
            .frame(height: 22)
            .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            Group {
                if appState.fileListMode == .list { plainContent }
                else { treeContent(visibleRows, toggleFolder) }
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .onAppear {
            if appState.fileListMode == .tree && roots.isEmpty && !items.isEmpty { rebuildTree() }
        }
        .onChange(of: items) { rebuildTree() }
        .onChange(of: appState.fileListMode) {
            if appState.fileListMode == .tree { rebuildTree() }
        }
    }

    private func rebuildTree() {
        let oldFolders = folderPaths
        roots = buildNodes(items)
        folderPaths = collectFolderPaths(roots)
        expandedFolders.formUnion(folderPaths.subtracting(oldFolders))
        expandedFolders.formIntersection(folderPaths)
        rebuildVisibleRows()
    }

    private func buildNodes(_ items: [Item]) -> [Node] {
        let groups = Dictionary(grouping: items) { item in
            String(path(item).split(separator: "/", omittingEmptySubsequences: true).first ?? "")
        }
        return groups.compactMap { name, groupedItems -> Node? in
            guard !name.isEmpty else { return nil }
            if let item = groupedItems.first(where: { path($0) == name }) {
                return Node(id: name, name: name, item: item, children: [])
            }
            return buildNode(name: name, fullPath: name, items: groupedItems)
        }.sorted(by: nodeOrder)
    }

    private func buildNode(name: String, fullPath: String, items: [Item]) -> Node {
        let prefix = fullPath + "/"
        let groups = Dictionary(grouping: items) { item in
            String(path(item).dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: true).first ?? "")
        }
        let children = groups.compactMap { childName, groupedItems -> Node? in
            guard !childName.isEmpty else { return nil }
            let childPath = prefix + childName
            if let item = groupedItems.first(where: { path($0) == childPath }) {
                return Node(id: childPath, name: childName, item: item, children: [])
            }
            return buildNode(name: childName, fullPath: childPath, items: groupedItems)
        }.sorted(by: nodeOrder)
        return Node(id: fullPath, name: name, item: nil, children: children)
    }

    private func nodeOrder(_ lhs: Node, _ rhs: Node) -> Bool {
        if (lhs.item == nil) != (rhs.item == nil) { return lhs.item == nil }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func collectFolderPaths(_ nodes: [Node]) -> Set<String> {
        var paths = Set<String>()
        func collect(_ nodes: [Node]) {
            for node in nodes where node.item == nil { paths.insert(node.id); collect(node.children) }
        }
        collect(nodes)
        return paths
    }

    private func rebuildVisibleRows() {
        var rows: [FilePathTreeRow<Item>] = []
        func append(_ nodes: [Node], depth: Int) {
            for node in nodes {
                if let item = node.item {
                    rows.append(.init(id: node.id, depth: depth, content: .file(item: item, name: node.name)))
                } else {
                    rows.append(.init(id: node.id, depth: depth, content: .folder(
                        path: node.id, name: node.name, items: descendantItems(node),
                        isExpanded: expandedFolders.contains(node.id)
                    )))
                    if expandedFolders.contains(node.id) { append(node.children, depth: depth + 1) }
                }
            }
        }
        append(roots, depth: 0)
        visibleRows = rows
    }

    private func descendantItems(_ node: Node) -> [Item] {
        var result: [Item] = []
        func append(_ node: Node) {
            if let item = node.item { result.append(item) } else { node.children.forEach(append) }
        }
        append(node)
        return result
    }

    private func toggleFolder(_ path: String) {
        if expandedFolders.contains(path) { expandedFolders.remove(path) } else { expandedFolders.insert(path) }
        rebuildVisibleRows()
    }

    private func expandAll() { expandedFolders = folderPaths; rebuildVisibleRows() }
    private func collapseAll() { expandedFolders.removeAll(keepingCapacity: true); rebuildVisibleRows() }

    private struct Node {
        let id: String
        let name: String
        let item: Item?
        let children: [Node]
    }
}
