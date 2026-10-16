// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryProviderIcon: View {
    let name: String

    var body: some View {
        if name == "code-branch" {
            Image(systemName: "externaldrive")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        } else {
            Image(name)
                .resizable()
                .scaledToFit()
        }
    }
}
