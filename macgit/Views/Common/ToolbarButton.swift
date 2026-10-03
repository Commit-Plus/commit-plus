//
//  ToolbarButton.swift
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

struct ToolbarButtonLabel: View {
    let icon: String
    let label: String
    var showText: Bool = true
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
            if showText {
                Text(label)
                    .font(.system(size: 9).scaled(by: textScale))
            }
        }
        .frame(width: 40 * textScale, height: 28)
    }
}

func toolbarButton(icon: String, label: String, showText: Bool = true, isLoading: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        ZStack {
            ToolbarButtonLabel(icon: icon, label: label, showText: showText)
                .opacity(isLoading ? 0.3 : 1.0)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        // Center the complete custom label, rather than an icon/text baseline.
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] }
    }
    .repositoryToolbarButtonStyle()
    .help(label)
    .disabled(disabled || isLoading)
}
