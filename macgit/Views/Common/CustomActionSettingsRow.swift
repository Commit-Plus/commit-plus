// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct CustomActionSettingsRow: View {
    let action: CustomActionDefinition
    let effectiveAction: CustomActionDefinition
    let isTrusted: Bool
    let onToggle: (Bool) -> Void
    let onReview: () -> Void
    let onLocate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(action.name, isOn: Binding(
                get: { action.isEnabled },
                set: onToggle
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(action.name)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if needsExecutable {
                Button("Locate…", action: onLocate)
            } else if !isTrusted {
                Button("Review…", action: onReview)
            } else {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        switch action.sourceKind {
        case .executable: effectiveAction.executablePath
        case .localScript: effectiveAction.executablePath
        case .syncedScript: "Synced \(action.scriptLanguage?.displayName ?? "script")"
        }
    }

    private var needsExecutable: Bool {
        guard action.sourceKind != .syncedScript else { return false }
        return !FileManager.default.fileExists(atPath: effectiveAction.executablePath)
    }
}
