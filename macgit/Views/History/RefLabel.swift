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

    var displayText: String {
        if text.hasPrefix("HEAD -> ") {
            return String(text.dropFirst(8))
        }
        if text.hasPrefix("tag: ") {
            return String(text.dropFirst(5))
        }
        return text
    }

    var isTag: Bool {
        text.hasPrefix("tag: ")
    }

    var backgroundColor: Color {
        if isTag {
            return Color(nsColor: .systemPurple).opacity(0.15)
        }
        if let graphColorIndex {
            return GraphPalette.color(for: graphColorIndex).opacity(0.2)
        }
        return Color.accentColor.opacity(0.15)
    }

    var textColor: Color {
        if isTag {
            return Color(nsColor: .systemPurple)
        }
        if let graphColorIndex {
            return GraphPalette.color(for: graphColorIndex)
        }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isTag ? "tag" : "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))

            Text(displayText)
                .font(.system(size: 11, weight: .semibold).scaled(by: textScale))
        }
        .lineLimit(1)
        .foregroundStyle(
            backgroundProminence == .increased
                ? AnyShapeStyle(.primary)
                : AnyShapeStyle(textColor)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(
            backgroundProminence == .increased
                ? Color.primary.opacity(0.12)
                : backgroundColor
        )
        .clipShape(Capsule())
    }
}
