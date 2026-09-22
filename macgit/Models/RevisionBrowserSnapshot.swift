// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct RevisionBrowserSnapshot: Sendable {
    let commitID: String
    let subject: String
    let changedNodePaths: Set<String>

    init(commitID: String, subject: String, changedPaths: [String] = []) {
        self.commitID = commitID
        self.subject = subject
        var nodes: Set<String> = []
        for path in changedPaths {
            var components = path.split(separator: "/").map(String.init)
            while !components.isEmpty {
                nodes.insert(components.joined(separator: "/"))
                components.removeLast()
            }
        }
        self.changedNodePaths = nodes
    }
}
