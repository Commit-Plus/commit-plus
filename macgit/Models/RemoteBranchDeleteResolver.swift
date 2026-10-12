// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum RemoteBranchDeleteResolver {
    static func target(
        localBranch: String,
        upstream: String?,
        branchesByRemote: [String: [String]]
    ) -> RemoteBranchDeleteTarget? {
        if let upstream,
           let tracked = RemoteBranchDeleteTarget(fullPath: upstream) {
            return tracked
        }

        let matches = branchesByRemote
            .filter { $0.value.contains(localBranch) }
            .map { RemoteBranchDeleteTarget(remote: $0.key, branch: localBranch) }
            .sorted { $0.fullPath < $1.fullPath }

        if let origin = matches.first(where: { $0.remote == "origin" }) {
            return origin
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
