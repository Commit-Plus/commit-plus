// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func imageData(from source: ImageComparisonRequest.Source, in repositoryURL: URL) async throws -> Data {
        switch source {
        case let .revision(ref, path):
            return try await showFile(at: path, ref: ref, in: repositoryURL)
        case let .index(path):
            return try await indexFile(at: path, in: repositoryURL)
        case let .indexWithFallback(path, originalPath):
            // Paired worktree renames may have either path in the index.
            do {
                return try await indexFile(at: path, in: repositoryURL)
            } catch {
                try Task.checkCancellation()
                guard path != originalPath else { throw error }
                return try await indexFile(at: originalPath, in: repositoryURL)
            }
        case let .disk(path):
            return try await Task.detached(priority: .userInitiated) {
                let root = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
                let file = repositoryURL.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
                let rootComponents = root.pathComponents
                guard file.pathComponents.count > rootComponents.count,
                      Array(file.pathComponents.prefix(rootComponents.count)) == rootComponents else {
                    throw GitError.commandFailed("Image preview paths must remain inside the repository.")
                }
                return try Data(contentsOf: file)
            }.value
        }
    }
}
