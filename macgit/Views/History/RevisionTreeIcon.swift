// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RevisionTreeIcon: View {
    private let path: String
    private let isDirectory: Bool
    private let isSubmodule: Bool
    private let isSymlink: Bool
    let isExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(entry: RevisionTreeEntry, isExpanded: Bool) {
        path = entry.path
        isDirectory = entry.isDirectory
        isSubmodule = entry.isSubmodule
        isSymlink = entry.isSymlink
        self.isExpanded = isExpanded
    }

    init(path: String, isDirectory: Bool, isExpanded: Bool = false) {
        self.path = path
        self.isDirectory = isDirectory
        self.isExpanded = isExpanded
        isSubmodule = false
        isSymlink = false
    }

    var body: some View {
        Group {
            if isSubmodule {
                Image(systemName: "shippingbox")
            } else if isSymlink {
                Image(systemName: "link")
            } else if let icons = RevisionMaterialIcons.shared {
                Image("revision-material-" + icons.icon(for: path, isDirectory: isDirectory,
                    isExpanded: isExpanded, isLight: colorScheme == .light))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: isDirectory ? "folder" : "doc.text")
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
