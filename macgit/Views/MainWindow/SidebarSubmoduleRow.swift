//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import SwiftUI

struct SidebarSubmoduleRow: View {
    let entry: GitSubmoduleEntry
    let onOpen: () -> Void
    let onShowInFinder: () -> Void
    let onOpenInTerminal: () -> Void
    let onInitialize: () -> Void
    let onUpdateToRecordedCommit: () -> Void
    let onUpdateFromRemote: () -> Void
    let onSynchronizeURL: () -> Void
    let onEditSettings: () -> Void
    let onDeinitialize: () -> Void
    let onRemove: () -> Void

    private var actions: Set<SubmoduleSidebarAction> {
        SubmoduleSidebarPolicy.actions(for: entry)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.state.systemImage)
                .foregroundStyle(entry.state.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .lineLimit(1)
                Text(entry.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if let branch = entry.branch {
                Text(branch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(entry.state.title)
                .font(.caption)
                .foregroundStyle(entry.state.tint)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                openIfAvailable()
            }
        )
        .contextMenu {
            if actions.contains(.openInCommitPlus) {
                Button("Open in Commit+", systemImage: "macwindow", action: onOpen)
            }
            if actions.contains(.showInFinder) {
                Button("Show in Finder", systemImage: "folder", action: onShowInFinder)
            }
            if actions.contains(.openInTerminal) {
                Button("Open in Terminal", systemImage: "terminal", action: onOpenInTerminal)
            }
            if actions.contains(.initialize) {
                Button("Initialize", systemImage: "arrow.down.square", action: onInitialize)
            }
            if actions.contains(.updateToRecordedCommit) {
                Button("Update to Recorded Commit", systemImage: "arrow.triangle.2.circlepath", action: onUpdateToRecordedCommit)
            }
            if actions.contains(.updateFromRemote) {
                Button("Update from Remote...", systemImage: "arrow.triangle.2.circlepath.circle", action: onUpdateFromRemote)
            }
            if actions.contains(.synchronizeURL) {
                Button("Synchronize URL", systemImage: "arrow.triangle.merge", action: onSynchronizeURL)
            }
            if actions.contains(.editSettings) {
                Button("Edit Submodule Settings...", systemImage: "slider.horizontal.3", action: onEditSettings)
            }
            if actions.contains(.deinitialize) {
                Button("Deinitialize...", systemImage: "externaldrive.badge.minus", action: onDeinitialize)
            }
            if actions.contains(.remove) {
                Button("Remove Submodule...", systemImage: "trash", role: .destructive, action: onRemove)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: "Open in Commit+", openIfAvailable)
    }

    private var displayName: String {
        // The tree already renders ancestor folders as folder nodes, so only
        // the leaf segment is shown as the title (custom --name values without
        // a slash are shown in full). The full path stays in the subtitle.
        entry.name.split(separator: "/").last.map(String.init) ?? entry.name
    }

    private var accessibilityLabel: String {
        if let branch = entry.branch {
            return "\(displayName), \(entry.path), branch \(branch), \(entry.state.title)"
        }
        return "\(displayName), \(entry.path), \(entry.state.title)"
    }

    private func openIfAvailable() {
        guard actions.contains(.openInCommitPlus) else { return }
        onOpen()
    }
}

private extension GitSubmoduleState {
    var title: String {
        switch self {
        case .clean: "Clean"
        case .modified: "Modified"
        case .newCommits: "New commits"
        case .uninitialized: "Not initialized"
        case .missing: "Missing"
        case .conflict: "Conflict"
        }
    }

    var systemImage: String {
        switch self {
        case .clean: "checkmark.circle.fill"
        case .modified: "pencil.circle.fill"
        case .newCommits: "arrow.triangle.2.circlepath.circle.fill"
        case .uninitialized: "circle.dashed"
        case .missing: "exclamationmark.triangle.fill"
        case .conflict: "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .clean: .green
        case .modified: .orange
        case .newCommits: .blue
        case .uninitialized: .secondary
        case .missing, .conflict: .red
        }
    }
}
