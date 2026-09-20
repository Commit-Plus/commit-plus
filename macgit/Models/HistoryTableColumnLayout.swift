// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct HistoryTableColumnLayout: Codable {
    private(set) var widths: [String: Double]
    private(set) var viewportWidth: Double

    var isValid: Bool {
        viewportWidth.isFinite && viewportWidth > 0
            && ["graph", "message", "author", "date", "commit"].allSatisfy {
                guard let width = widths[$0] else { return false }
                return width.isFinite && width > 0
            }
    }

    func width(for column: String, viewportWidth: Double, minimumWidth: Double) -> Double {
        max(minimumWidth, (widths[column] ?? minimumWidth) * viewportWidth / self.viewportWidth)
    }

    mutating func resizeColumn(_ column: String, to width: Double, viewportWidth: Double) {
        // Rebase all columns, including hidden ones, without baking temporary
        // minimum-width constraints into the user's saved proportions.
        let scale = viewportWidth / self.viewportWidth
        widths = widths.mapValues { $0 * scale }
        widths[column] = width
        self.viewportWidth = viewportWidth
    }
}
