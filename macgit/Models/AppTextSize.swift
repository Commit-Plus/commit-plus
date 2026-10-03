// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

enum AppTextSize: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case large
    case extraLarge

    var id: Self { self }

    var title: String {
        switch self {
        case .default: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .default: 1
        case .large: 1.15
        case .extraLarge: 1.3
        }
    }

    var font: Font {
        .body.scaled(by: scale)
    }
}

private struct AppTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var appTextScale: CGFloat {
        get { self[AppTextScaleKey.self] }
        set { self[AppTextScaleKey.self] = newValue }
    }
}
