// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RevisionTreeIcon: View {
    let entry: RevisionTreeEntry
    let isExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if entry.isSubmodule {
                Image(systemName: "shippingbox")
            } else if entry.isSymlink {
                Image(systemName: "link")
            } else if let icons = RevisionMaterialIcons.shared {
                Image("revision-material-" + icons.icon(for: entry.path, isDirectory: entry.isDirectory,
                    isExpanded: isExpanded, isLight: colorScheme == .light))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: entry.isDirectory ? "folder" : "doc.text")
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
