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

/// Read-only file content with line numbers, backed by a native table so large files scroll smoothly.
struct CommitFilePreviewContent: View {
    @ObservedObject private var advancedSettings = AdvancedSettingsStore.shared
    let lines: [DiffLine]
    let fileExtension: String
    /// Drops the card chrome so the content can sit flush next to other panes.
    var embedded = false
    var onVerticalOffsetChange: ((CGFloat) -> Void)? = nil

    var body: some View {
        CodeLinesNativeView(lines: lines, fileExtension: fileExtension,
            highlightsSyntax: advancedSettings.diffSyntaxHighlighting,
            onVerticalOffsetChange: onVerticalOffsetChange)
            .background(.secondary.opacity(embedded ? 0 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: embedded ? 0 : 8, style: .continuous))
            .overlay {
                if !embedded {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.separator.opacity(0.5), lineWidth: 0.5)
                }
            }
            .padding(embedded ? 0 : 12)
    }
}
