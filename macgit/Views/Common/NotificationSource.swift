// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum NotificationSource: String, CaseIterable, Identifiable {
    case app
    case github

    var id: Self { self }

    var title: String {
        switch self {
        case .app: "App notifications"
        case .github: "GitHub notifications"
        }
    }
}
