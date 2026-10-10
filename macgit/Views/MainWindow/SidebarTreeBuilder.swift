//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation

struct SidebarTreeBuilder {
    static func buildTree(from refs: [String], prefix: String = "") -> [BranchNode] {
        SidebarSignpost.interval("BuildTree") {
            buildTreeContents(from: refs, prefix: prefix)
        }
    }

    private static func buildTreeContents(from refs: [String], prefix: String) -> [BranchNode] {
        var groups = [String: [String]]()
        var leaves = Set<String>()

        for ref in refs {
            let relative = prefix.isEmpty ? ref : String(ref.dropFirst(prefix.count + 1))
            if let slashIndex = relative.firstIndex(of: "/") {
                let first = String(relative[..<slashIndex])
                groups[first, default: []].append(ref)
            } else {
                leaves.insert(relative)
            }
        }

        var nodes: [BranchNode] = []

        for (name, childRefs) in groups.sorted(by: { $0.key < $1.key }) {
            let fullPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            var children = buildTreeContents(from: childRefs, prefix: fullPath)
            if leaves.remove(name) != nil {
                children.insert(
                    BranchNode(name: name, fullPath: fullPath, isFolder: false, children: []),
                    at: 0
                )
            }
            nodes.append(BranchNode(name: name, fullPath: fullPath, isFolder: true, children: children))
        }

        for leaf in leaves.sorted() {
            let fullPath = prefix.isEmpty ? leaf : "\(prefix)/\(leaf)"
            nodes.append(BranchNode(name: leaf, fullPath: fullPath, isFolder: false, children: []))
        }

        return nodes
    }

    static func buildRemoteTree(remoteBranchesByRemote: [String: [String]]) -> [BranchNode] {
        remoteBranchesByRemote.keys.sorted().map { remote in
            let branchRefs = remoteBranchesByRemote[remote, default: []]
                .map(normalizedRemoteBranchName)
                .filter { !$0.isEmpty }
                .map { "\(remote)/\($0)" }

            return BranchNode(
                name: remote,
                fullPath: remote,
                isFolder: true,
                children: buildTree(from: branchRefs, prefix: remote)
            )
        }
    }

    static func expandedFolderPaths(revealing ref: String) -> Set<String> {
        let parts = ref
            .split(separator: "/")
            .map(String.init)

        guard parts.count > 1 else {
            return []
        }

        var paths = Set<String>()
        for index in parts.indices.dropLast() {
            paths.insert(parts[...index].joined(separator: "/"))
        }
        return paths
    }

    static func visibleRows(from nodes: [BranchNode], expandedFolders: Set<String>) -> [BranchRowItem] {
        SidebarSignpost.interval("VisibleRows") {
            var rows: [BranchRowItem] = []

            func traverse(_ nodes: [BranchNode], indent: Int) {
                for node in nodes {
                    rows.append(BranchRowItem(
                        id: node.id,
                        name: node.name,
                        fullPath: node.fullPath,
                        isFolder: node.isFolder,
                        indent: indent
                    ))
                    if node.isFolder && expandedFolders.contains(node.fullPath) {
                        traverse(node.children, indent: indent + 1)
                    }
                }
            }

            traverse(nodes, indent: 0)
            return rows
        }
    }

    nonisolated private static func normalizedRemoteBranchName(_ branch: String) -> String {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("HEAD -> ") {
            return "HEAD"
        }
        return trimmed
    }
}
