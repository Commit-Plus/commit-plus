// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func imageData(from source: ImageComparisonRequest.Source, in repositoryURL: URL) async throws -> Data {
        switch source {
        case let .revision(ref, path):
            return try await showFile(at: path, ref: ref, in: repositoryURL)
        case let .index(path):
            return try await indexFile(at: path, in: repositoryURL)
        case let .disk(path):
            return try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: repositoryURL.appendingPathComponent(path))
            }.value
        }
    }
}
