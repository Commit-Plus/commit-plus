// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct CustomActionSettingsRow: View {
    let action: CustomActionDefinition
    let effectiveAction: CustomActionDefinition
    let isTrusted: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.name)
                    .lineLimit(1)
                    .foregroundStyle(action.isEnabled ? .primary : .secondary)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if status != .ready {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.color)
                    .help(status.title)
                    .accessibilityLabel(status.title)
            }
        }
        .padding(.vertical, 3)
    }

    private var detail: String {
        switch action.sourceKind {
        case .executable, .localScript: (effectiveAction.executablePath as NSString).lastPathComponent
        case .syncedScript: "Synced \(action.scriptLanguage?.displayName ?? "script")"
        }
    }

    private var status: CustomActionStatus {
        CustomActionStatus(action: action, effectiveAction: effectiveAction, isTrusted: isTrusted)
    }
}
