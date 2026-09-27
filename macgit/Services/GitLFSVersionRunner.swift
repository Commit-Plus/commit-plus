// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSVersionRunner: GitRuntimeProcessRunning {
    func version(at executableURL: URL) async throws -> String {
        let version = try await ProcessGitRuntimeRunner().version(at: executableURL)
        guard Self.isSupported(version) else {
            throw GitError.commandFailed("Git LFS 3.8 or later is required. Download Embedded Git LFS to continue.")
        }
        return version
    }

    nonisolated static func isSupported(_ version: String) -> Bool {
        guard version.hasPrefix("git-lfs/"), let number = version.dropFirst(8).split(separator: " ").first else { return false }
        let parts = number.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 8)
    }
}
