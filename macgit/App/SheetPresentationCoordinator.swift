// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One coordinator per presentation level, scoped to a single window.
@MainActor
final class SheetPresentationCoordinator {
    var isPresenting: Bool { activeID != nil }

    private var activeID: UUID?
    private var dismissActive: (() -> Void)?

    func present(_ id: UUID, dismiss: @escaping () -> Void) {
        guard activeID != id else { return }
        let dismissPrevious = dismissActive
        activeID = id
        dismissActive = dismiss
        // Clear the SwiftUI source binding, so its normal dismissal callbacks run.
        // SwiftUI completes the outgoing sheet before displaying the new one.
        dismissPrevious?()
    }

    func release(_ id: UUID) {
        guard activeID == id else { return }
        activeID = nil
        dismissActive = nil
    }
}
