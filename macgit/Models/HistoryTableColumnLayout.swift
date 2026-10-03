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

    func width(for column: String, minimumWidth: Double) -> Double {
        max(minimumWidth, widths[column] ?? minimumWidth)
    }

    mutating func resizeColumn(_ column: String, to width: Double, viewportWidth: Double) {
        // Persist only the column the user resized. Other columns, including
        // hidden ones, retain their absolute widths.
        widths[column] = width
        self.viewportWidth = viewportWidth
    }
}
