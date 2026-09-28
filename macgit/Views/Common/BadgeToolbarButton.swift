//
//  BadgeToolbarButton.swift
//  macgit
//

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

struct BadgeToolbarButton: View {
    let icon: String
    let label: String
    let badgeCount: Int
    let isLoading: Bool
    let disabled: Bool
    var showText: Bool = true
    let action: () -> Void

    private var badgeText: String {
        return String(badgeCount)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ToolbarButtonLabel(icon: icon, label: label, showText: showText)
                    .opacity(isLoading ? 0.3 : 1.0)

                if badgeCount > 0 && !isLoading {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white, lineWidth: 1)
                        )
                        .offset(x: 8, y: -4)
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // Keep badge text from changing the toolbar label's alignment.
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] }
        }
        .help(label)
        .disabled(disabled || isLoading)
    }
}

#Preview {
    HStack {
        BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: 3, isLoading: false, disabled: false, action: {})
        BadgeToolbarButton(icon: "arrow.up.to.line", label: "Push", badgeCount: 105, isLoading: true, disabled: false, action: {})
        BadgeToolbarButton(icon: "arrow.down.to.line", label: "Pull", badgeCount: 0, isLoading: false, disabled: true, action: {})
    }
    .padding()
}
