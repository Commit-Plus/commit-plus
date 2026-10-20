// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum AccountWelcomeState: Equatable {
    case neutral
    case free
    case pro
}

/// The authentication sheet that started an interactive sign-in and owns its welcome.
enum AccountWelcomeHost: Hashable {
    /// The sheet presented through `AccountSessionController.presentedSheet`.
    case controllerSheet
    /// A sheet presented locally by a settings pane or gate, identified per presentation.
    case localSheet(UUID)
}

struct AccountWelcome: Equatable {
    let uid: String
    let host: AccountWelcomeHost
    var state: AccountWelcomeState = .neutral
    /// Set while a mandatory settings-conflict sheet has replaced the controller welcome sheet.
    var isDeferred = false
}
