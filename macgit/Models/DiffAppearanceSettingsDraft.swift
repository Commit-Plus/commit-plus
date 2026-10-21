// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit

struct DiffAppearanceSettingsDraft: Equatable {
    var fontName: String
    var fontSize: Double
    var addedBackgroundColor: NSColor
    var addedTextColor: NSColor
    var removedBackgroundColor: NSColor
    var removedTextColor: NSColor

    var font: NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}
