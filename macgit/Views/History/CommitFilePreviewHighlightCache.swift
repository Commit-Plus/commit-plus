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

@MainActor
final class CommitFilePreviewHighlightCache {
    private var entries: [UUID: AttributedString] = [:]
    private var insertionOrder: [UUID] = []
    private let capacity = 512

    func text(for line: DiffLine, fileExtension: String) -> AttributedString? {
        guard !DiffLongLineLayout.isLong(line.text) else { return nil }
        if let cached = entries[line.id] { return cached }
        let highlighted = SyntaxHighlighter(fileExtension: fileExtension)
            .attributedString(for: line.text, fontSize: 12)
        if insertionOrder.count == capacity {
            entries.removeValue(forKey: insertionOrder.removeFirst())
        }
        entries[line.id] = highlighted
        insertionOrder.append(line.id)
        return highlighted
    }
}
