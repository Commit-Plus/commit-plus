// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The pending cloud uploads of each open repository window. Closing a window runs its own
/// upload; quitting runs every open window's, because windows still open at quit reach
/// `onDisappear` only after `applicationWillTerminate`, when async work no longer runs.
@MainActor
final class RepositoryWindowCloudSyncRegistry {
    static let shared = RepositoryWindowCloudSyncRegistry()

    private var uploads: [UUID: () async -> Void] = [:]
    /// Uploads started by closed windows, kept until they finish so quitting still awaits them.
    private var inFlightUploads: [UUID: Task<Void, Never>] = [:]

    func register(_ id: UUID, upload: @escaping () async -> Void) {
        uploads[id] = upload
    }

    /// Unregisters a closing window and starts its upload.
    func uploadAndUnregister(_ id: UUID) {
        guard let upload = uploads.removeValue(forKey: id) else { return }
        inFlightUploads[id] = Task {
            await upload()
            inFlightUploads[id] = nil
        }
    }

    func uploadAll() async {
        let tasks = uploads.values.map { upload in Task { await upload() } }
            + Array(inFlightUploads.values)
        for task in tasks { await task.value }
    }
}
