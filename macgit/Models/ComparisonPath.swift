// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct ComparisonPath: Equatable, Sendable, Identifiable {
    let path: String
    let isDirectory: Bool
    var id: String { "\(isDirectory):\(path)" }

    func validate() throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0.isEmpty }),
              path == "." || !path.split(separator: "/").contains(".") else {
            throw GitError.commandFailed("Select a repository-relative file or folder.")
        }
    }

    func contains(_ candidate: String) -> Bool {
        candidate == path || (isDirectory && (path == "." || candidate.hasPrefix(path + "/")))
    }
}
