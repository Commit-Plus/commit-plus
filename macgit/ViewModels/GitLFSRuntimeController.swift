// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

@MainActor @Observable
final class GitLFSRuntimeController {
    static let shared = GitLFSRuntimeController()
    var status: GitRuntimeStatus?
    var isInstalling = false
    var error: String?
    private var installation: Task<Bool, Never>?

    var downloadDescription: String {
        let manifest = GitLFSRuntime.manifest
        return "Git LFS \(manifest.version) · \(ByteCountFormatter.string(fromByteCount: Int64(manifest.archiveSize), countStyle: .file))"
    }

    func refresh() async { status = await GitLFSRuntime.shared.status() }

    func select(_ preference: GitRuntimePreference) async {
        do { try await GitLFSRuntime.shared.select(preference); error = nil }
        catch { self.error = Self.message(error) }
        await refresh()
    }

    @discardableResult
    func install() async -> Bool {
        if let installation { return await installation.value }
        isInstalling = true
        error = nil
        let task = Task { () -> Bool in
            do {
                try await GitLFSRuntime.shared.install()
                await refresh()
                return true
            } catch {
                if !Task.isCancelled { self.error = Self.message(error) }
                await refresh()
                return false
            }
        }
        installation = task
        let succeeded = await task.value
        installation = nil
        isInstalling = false
        return succeeded
    }

    func cancel() { installation?.cancel() }

    private static func message(_ error: Error) -> String {
        error.localizedDescription.replacingOccurrences(of: "Embedded Git", with: "Embedded Git LFS")
            .replacingOccurrences(of: "System Git is", with: "System Git LFS is")
    }
}
