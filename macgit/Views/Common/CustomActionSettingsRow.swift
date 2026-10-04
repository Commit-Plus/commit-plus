// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct CustomActionSettingsRow: View {
    let action: CustomActionDefinition
    let effectiveAction: CustomActionDefinition
    let isTrusted: Bool
    let onRemove: () -> Void
    let onDuplicate: () -> Void
    let onEdit: () -> Void
    let onReview: () -> Void
    let onLocate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.name)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(detail)
            }

            Spacer()

            if !action.isEnabled {
                Text("Disabled").foregroundStyle(.secondary)
            }
            if needsExecutable {
                Button("Locate…", action: onLocate)
            } else if !isTrusted {
                Button("Review…", action: onReview)
            } else {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }

            HStack(spacing: 8) {
                Button("Remove", systemImage: "trash", action: onRemove)
                    .help("Remove \(action.name)")
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    .help("Duplicate \(action.name)")
                Button("Edit", systemImage: "pencil", action: onEdit)
                    .help("Edit \(action.name)")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
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
