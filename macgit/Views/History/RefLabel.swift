//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import SwiftUI

struct RefLabel: View {
    let text: String
    let graphColorIndex: Int?
    @Environment(\.backgroundProminence) private var backgroundProminence
    @Environment(\.appTextScale) private var textScale

    init(text: String, graphColorIndex: Int? = nil) {
        self.text = text
        self.graphColorIndex = graphColorIndex
    }

    private var style: RefLabelStyle {
        RefLabelStyle(text: text, graphColorIndex: graphColorIndex)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: style.symbolName)
                .font(.system(size: 10, weight: .semibold))

            Text(style.displayText)
                .font(.system(size: 11, weight: .semibold).scaled(by: textScale))
        }
        .lineLimit(1)
        .foregroundStyle(
            backgroundProminence == .increased
                ? AnyShapeStyle(.primary)
                : AnyShapeStyle(Color(nsColor: style.foreground))
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(
            backgroundProminence == .increased
                ? Color.primary.opacity(0.12)
                : Color(nsColor: style.background)
        )
        .clipShape(Capsule())
    }
}

/// Native badge appearance shared by SwiftUI and AppKit History surfaces.
struct RefLabelStyle {
    let displayText: String
    let isTag: Bool
    let symbolName: String
    let foreground: NSColor
    let background: NSColor

    init(text: String, graphColorIndex: Int?) {
        isTag = text.hasPrefix("tag: ")
        if text.hasPrefix("HEAD -> ") {
            displayText = String(text.dropFirst(8))
        } else if isTag {
            displayText = String(text.dropFirst(5))
        } else {
            displayText = text
        }
        symbolName = isTag ? "tag" : "arrow.triangle.branch"
        if isTag {
            foreground = .systemPurple
            background = foreground.withAlphaComponent(0.15)
        } else if let graphColorIndex {
            foreground = GraphPalette.nsColor(for: graphColorIndex)
            background = foreground.withAlphaComponent(0.2)
        } else {
            foreground = .controlAccentColor
            background = foreground.withAlphaComponent(0.15)
        }
    }
}
