// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct PullRequestReviewContextView: View {
    @Environment(\.appTextScale) private var textScale
    let context: PullRequestReviewContext
    let webURL: URL
    @State private var hunks: [DiffHunk] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Link(destination: webURL) {
                    Text(context.path)
                        .font(.subheadline.monospaced().scaled(by: textScale))
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    if let line = context.line {
                        let range = context.startLine.map { "\($0)–\(line)" } ?? "\(line)"
                        Text("Lines \(range) · \(context.side == "LEFT" ? "Original" : "Modified")")
                    }
                    if context.isOutdated {
                        Text("Outdated")
                    }
                }
                .font(.caption.scaled(by: textScale))
                .foregroundStyle(.secondary)
            }
            .padding(10)

            if !hunks.isEmpty {
                Divider()
                DiffView(hunks: hunks, filePath: context.path, prefersTextDiff: true)
                    .frame(height: min(320, max(120, CGFloat(hunks.reduce(0) { $0 + $1.lines.count + 1 }) * 22 * textScale + 40)))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator, lineWidth: 0.5)
        }
        .task(id: context.diffHunk) {
            hunks = context.diffHunk.map { DiffParser.parse($0) } ?? []
        }
    }
}
