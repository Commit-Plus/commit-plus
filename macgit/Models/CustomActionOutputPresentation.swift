// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct CustomActionOutputPresentation: Identifiable {
    let id = UUID()
    let result: CustomActionExecutionResult
}
