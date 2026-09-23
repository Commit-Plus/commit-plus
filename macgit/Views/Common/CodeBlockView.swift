//
//  CodeBlockView.swift
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

struct CodeBlockView: View {
    let text: String
    let fileExtension: String
    let fontSize: CGFloat

    init(text: String, fileExtension: String, fontSize: CGFloat = 12) {
        self.text = text
        self.fileExtension = fileExtension
        self.fontSize = fontSize
    }

    @State private var lines: [String] = []
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(fileExtension.uppercased()).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy code", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(8)
            CodeRenderViewport(count: lines.count, rowHeight: fontSize + 8, minimumWidth: contentWidth) { index, viewport in
                HStack(spacing: 0) {
                    Text(String(index + 1))
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 48, alignment: .trailing)
                        .padding(.trailing, 8)
                    if DiffLongLineLayout.isLong(lines[index]) {
                        DiffLongLineContent(lineID: index, text: lines[index],
                                            viewport: viewport.offsetBy(dx: -56, dy: 0), fontSize: fontSize)
                    } else {
                        Text(SyntaxHighlighter(fileExtension: fileExtension)
                            .attributedString(for: lines[index], fontSize: fontSize))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer(minLength: 0)
                }
                .textSelection(.enabled)
            }
            .frame(height: min(400, max(fontSize + 8, CGFloat(lines.count) * (fontSize + 8))))
        }
        .background(.secondary.opacity(0.05), in: .rect(cornerRadius: 6))
        .task(id: text) {
            let source = text
            let worker = Task.detached(priority: .userInitiated) {
                let lines = source.components(separatedBy: "\n")
                let columns = lines.reduce(0) { max($0, $1.utf16.reduce(0) { $0 + ($1 == 9 ? 8 : 1) }) }
                return (lines, columns)
            }
            let (prepared, columns) = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            lines = prepared
            // Keep width stable as vertically offscreen rows are removed.
            contentWidth = CGFloat(columns) * NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).maximumAdvancement.width + 56
        }
    }
}
