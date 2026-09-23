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

struct PotentialConflictCodeBlockView: View {
    let block: PotentialConflictBlock
    let fileExtension: String

    @State private var minimumWidth: CGFloat = 0

    var body: some View {
        CodeRenderViewport(count: block.lines.count, rowHeight: 22, minimumWidth: minimumWidth) { index, viewport in
            let line = block.lines[index]
            HStack(spacing: 0) {
                Text(String(line.lineNumber))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, 8)
                if DiffLongLineLayout.isLong(line.text) {
                    DiffLongLineContent(lineID: line.id, text: line.text,
                                        viewport: viewport.offsetBy(dx: -56, dy: 0))
                        .padding(.horizontal, 8)
                } else {
                    Text(highlightedText(for: line))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(for: line))
            .textSelection(.enabled)
            .contextMenu {
                Button("Copy line") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(line.text, forType: .string)
                }
                Button("Copy block") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(block.lines.map(\.text).joined(separator: "\n"), forType: .string)
                }
            }
        }
        .frame(height: min(400, CGFloat(block.lines.count) * 22))
        .task(id: block.id) {
            let lines = block.lines
            let worker = Task.detached(priority: .userInitiated) {
                lines.reduce(0) { max($0, $1.text.utf16.reduce(0) { $0 + ($1 == 9 ? 8 : 1) }) }
            }
            let columns = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            minimumWidth = CGFloat(columns) * NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).maximumAdvancement.width + 64
        }
    }

    private func highlightedText(for line: PotentialConflictLine) -> AttributedString {
        var attributed = SyntaxHighlighter(fileExtension: fileExtension)
            .attributedString(for: line.text, fontSize: 12)

        if line.isMarker {
            attributed.foregroundColor = markerColor(for: line.region)
            attributed.backgroundColor = markerColor(for: line.region).opacity(0.16)
            attributed.font = .system(size: 12, weight: .semibold, design: .monospaced)
        }

        return attributed
    }

    private func rowBackground(for line: PotentialConflictLine) -> Color {
        if line.isMarker {
            return markerColor(for: line.region).opacity(0.16)
        }

        switch line.region {
        case .context:
            return .clear
        case .local:
            return Color.red.opacity(0.10)
        case .mergeBase:
            return Color.orange.opacity(0.08)
        case .incoming:
            return Color.green.opacity(0.10)
        }
    }

    private func markerColor(for region: PotentialConflictLineRegion) -> Color {
        switch region {
        case .context:
            return .secondary
        case .local:
            return .red
        case .mergeBase:
            return .orange
        case .incoming:
            return .green
        }
    }
}
