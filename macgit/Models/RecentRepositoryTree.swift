// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum RecentRepositoryTree {
    struct Row: Identifiable {
        enum Content {
            case folder(URL, count: Int)
            case repository(RecentRepository)
        }

        let id: String
        let depth: Int
        let content: Content
    }

    static func rows(
        repositories: [RecentRepository],
        expandedFolders: Set<URL>,
        expandAll: Bool = false,
        roots explicitRoots: [URL] = []
    ) -> [Row] {
        let parents = Set(explicitRoots.isEmpty ? repositories.map { $0.url.deletingLastPathComponent().path } : explicitRoots.map(\.path))
        let roots = parents.filter { path in
            !parents.contains { ancestor in
                ancestor != path && path.hasPrefix(ancestor == "/" ? "/" : ancestor + "/")
            }
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let expandedPaths = Set(expandedFolders.map(\.path))
        var result: [Row] = []

        func appendFolder(_ path: String, repositories: [RecentRepository], depth: Int) {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            result.append(Row(id: "folder:\(path)", depth: depth, content: .folder(folder, count: repositories.count)))
            guard expandAll || expandedPaths.contains(path) else { return }

            let direct = repositories.filter { $0.url.path == path || $0.url.deletingLastPathComponent().path == path }
            let descendants = repositories.filter { $0.url.path != path && $0.url.deletingLastPathComponent().path != path }
            let prefix = path == "/" ? "/" : path + "/"
            let children = Set(descendants.compactMap { repository -> String? in
                guard repository.url.path.hasPrefix(prefix),
                      let component = repository.url.path.dropFirst(prefix.count).split(separator: "/").first else { return nil }
                return prefix + component
            }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            for child in children {
                appendFolder(child, repositories: descendants.filter { $0.url.path.hasPrefix(child + "/") }, depth: depth + 1)
            }
            for repository in direct {
                result.append(Row(id: "repo:\(repository.url.path)", depth: depth + 1, content: .repository(repository)))
            }
        }

        for root in roots {
            let prefix = root == "/" ? "/" : root + "/"
            appendFolder(root, repositories: repositories.filter { $0.url.path == root || $0.url.path.hasPrefix(prefix) }, depth: 0)
        }
        return result
    }
}
