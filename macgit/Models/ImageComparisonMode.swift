// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated enum ImageComparisonMode: String, CaseIterable, Identifiable {
    case sideBySide
    case overlay
    var id: String { rawValue }
    var title: String { self == .overlay ? "Overlay Slider" : "Side by Side" }
    var icon: String { self == .overlay ? "slider.horizontal.below.rectangle" : "rectangle.split.2x1" }
}
