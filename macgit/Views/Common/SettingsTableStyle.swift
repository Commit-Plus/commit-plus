// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Rounded, bordered list used for editable item tables in Settings.
    func settingsTableStyle() -> some View {
        listStyle(.inset)
            .alternatingRowBackgrounds()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
    }

    /// Rounded panel beside a settings table that shows the selected item.
    func settingsDetailPanelStyle() -> some View {
        background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }
}
