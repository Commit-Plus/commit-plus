// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Long generated/minified lines stay scrollable without a giant SwiftUI Text.
struct DiffLongLineContent: View {
    let lineID: UUID
    let text: String
    let viewport: CGRect
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
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: chunk.width, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: layout.width, alignment: .leading)
            } else {
                Text("Preparing long line…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: lineID) {
            layout = nil
            let prepared = await DiffLongLineLayout.load(
                text: text, fontName: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName
            )
            guard !Task.isCancelled else { return }
            layout = prepared
        }
        .accessibilityLabel("Long line")
        .help("Long lines use plain text for performance. Copy includes the entire line.")
    }
}
