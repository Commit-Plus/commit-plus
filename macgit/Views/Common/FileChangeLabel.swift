// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct FileChangeLabel<Accessory: View>: View {
    @Environment(\.appTextScale) private var textScale
    let name: String
    let path: String
    let counts: FileLineChangeCount?
    var nameFontSize: CGFloat = 13
    var pathColor: HierarchicalShapeStyle = .secondary
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: nameFontSize, weight: .medium).scaled(by: textScale))
                    .lineLimit(1)
                    .truncationMode(.middle)
                accessory()
            }
            HStack(spacing: 6) {
                Text(path)
                    .font(.system(size: 10).scaled(by: textScale))
                    .foregroundStyle(pathColor)
                    .lineLimit(1)
                if let counts {
                    HStack(spacing: 4) {
                        Text("+\(counts.added)").foregroundStyle(.green)
                        Text("-\(counts.removed)").foregroundStyle(.red)
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced).scaled(by: textScale))
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(counts.added) lines added, \(counts.removed) lines removed")
                }
            }
        }
    }
}
