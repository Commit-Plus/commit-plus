// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SettingsActionRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content
        }
    }
}
