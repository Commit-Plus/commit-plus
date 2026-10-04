// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct CustomActionCommandState {
    let context: CustomActionInvocationContext
    let surface: CustomActionInvocationSurface
    let hasActiveOperation: Bool
    let run: (UUID, CustomActionInvocationSurface) -> Void
}

struct CustomActionCommandStateKey: FocusedValueKey {
    typealias Value = CustomActionCommandState
}

extension FocusedValues {
    var customActionCommandState: CustomActionCommandState? {
        get { self[CustomActionCommandStateKey.self] }
        set { self[CustomActionCommandStateKey.self] = newValue }
    }
}
