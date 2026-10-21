// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The pending cloud uploads of each open repository window. Closing a window runs its own
/// upload; quitting runs every open window's, because windows still open at quit reach
/// `onDisappear` only after `applicationWillTerminate`, when async work no longer runs.
@MainActor
final class RepositoryWindowCloudSyncRegistry {
    static let shared = RepositoryWindowCloudSyncRegistry()

    private var uploads: [UUID: () async -> Void] = [:]

    func register(_ id: UUID, upload: @escaping () async -> Void) {
        uploads[id] = upload
    }

    func unregister(_ id: UUID) {
        uploads[id] = nil
    }

    func uploadAll() async {
        let tasks = uploads.values.map { upload in Task { await upload() } }
        for task in tasks { await task.value }
    }
}
