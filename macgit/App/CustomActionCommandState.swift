// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct CustomActionCommandState: Equatable {
    let context: CustomActionInvocationContext
    let surface: CustomActionInvocationSurface
    let hasActiveOperation: Bool
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

extension Notification.Name {
    static let customActionMenuAction = Notification.Name("macgit.customActionMenuAction")
}
