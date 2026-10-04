// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct CustomActionMenuContent: View {
    @ObservedObject var store: CustomActionStore
    let surface: CustomActionInvocationSurface
    let context: CustomActionInvocationContext
    var hasActiveOperation = false
    var includesRepositoryActions = false
    let onRun: (UUID, CustomActionInvocationSurface) -> Void

    private var actions: [CustomActionDefinition] {
        store.actions.filter {
            $0.isEnabled
                && ($0.availability.contains(surface.availability)
                    || (includesRepositoryActions && $0.availability.contains(.repository)))
        }
    }

    var body: some View {
        if actions.isEmpty {
            Text("No Custom Actions")
        } else {
            ForEach(actions) { action in
                let invocationSurface: CustomActionInvocationSurface = action.availability.contains(surface.availability)
                    ? surface
                    : .repository
                let reason = CustomActionValidator.unavailableReason(
                    for: store.effectiveAction(action),
                    surface: invocationSurface,
                    context: context,
                    isTrusted: store.isTrusted(action)
                )
                Button(action.name) { onRun(action.id, invocationSurface) }
                    .disabled(hasActiveOperation || reason != nil)
                    .help(reason ?? "Run \(action.name)")
            }
        }
    }
}
