// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Long generated/minified lines stay scrollable without a giant SwiftUI Text.
struct DiffLongLineContent<ID: Hashable>: View {
    let lineID: ID
    let text: String
    let viewport: CGRect
    var fontSize: CGFloat = 12
    @State private var contentVersion = 0
    @State private var layout: DiffLongLineLayout?

    var body: some View {
        Group {
            if let layout {
                let range = layout.visibleChunks(in: viewport)
                HStack(spacing: 0) {
                    if let first = range.first {
                        Color.clear.frame(width: layout.chunks[first].offset, height: 1)
                    }
                    ForEach(range, id: \.self) { index in
                        let chunk = layout.chunks[index]
                        Text(verbatim: String(layout.text[chunk.range]))
                            .font(.system(size: fontSize, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: chunk.width, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: layout.width, alignment: .leading)
            } else {
                Text("Preparing long line…")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: text) { contentVersion += 1 }
        .onChange(of: lineID) { contentVersion += 1 }
        .onChange(of: fontSize) { contentVersion += 1 }
        .task(id: contentVersion) {
            layout = nil
            let prepared = await DiffLongLineLayout.load(
                text: text, fontName: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).fontName,
                fontSize: fontSize
            )
            guard !Task.isCancelled else { return }
            layout = prepared
        }
        .accessibilityLabel("Long line")
        .help("Long lines use plain text for performance. Copy includes the entire line.")
    }
}
