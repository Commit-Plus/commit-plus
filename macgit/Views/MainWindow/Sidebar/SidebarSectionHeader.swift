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

struct SidebarSectionHeader<Trailing: View>: View {
    let section: SidebarSection
    let isExpanded: Bool
    let activeDropLabel: String?
    let onToggle: () -> Void
    @ViewBuilder let trailing: Trailing
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(section.iconColor)

                Text(section.rawValue)
                    .font(.system(size: 11).scaled(by: textScale))
                    .bold()
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            Spacer()
            if let activeDropLabel {
                Text(activeDropLabel)
                    .font(.system(size: 10, weight: .semibold).scaled(by: textScale))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            trailing
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.rawValue) section")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
        .accessibilityAddTraits(.isButton)
    }
}
