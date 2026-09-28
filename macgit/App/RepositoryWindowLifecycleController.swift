// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

@MainActor
final class RepositoryWindowLifecycleController {
    private var activeWindowIDs: Set<UUID> = []

    @discardableResult
    func windowDidAppear(id: UUID) -> Bool {
        activeWindowIDs.insert(id).inserted
    }

    func windowDidDisappear(id: UUID) -> Bool {
        guard activeWindowIDs.remove(id) != nil else { return false }
        return activeWindowIDs.isEmpty
    }

    var activeWindowCount: Int {
        activeWindowIDs.count
    }
}
