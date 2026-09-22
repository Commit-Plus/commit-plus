// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func repositoryBookmarkRemotes(in repositoryURL: URL) async throws -> [RepositoryBookmarkRemote] {
        let output = try await runGit(arguments: ["remote"], in: repositoryURL)
        var result: [RepositoryBookmarkRemote] = []
        for name in output.split(separator: "\n").map(String.init) {
            let url = try await runGit(arguments: ["remote", "get-url", name], in: repositoryURL)
            if let identity = RepositoryBookmarkIdentity.resolve(remoteURLString: url) {
                result.append(RepositoryBookmarkRemote(name: name, identity: identity))
            }
        }
        return result.sorted {
            if ($0.name == "origin") != ($1.name == "origin") { return $0.name == "origin" }
            return $0.name < $1.name
        }
    }
}
