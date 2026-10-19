// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct AppNotificationRow: View {
    let notification: AppNotification
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.repositoryURL.lastPathComponent)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(notification.createdAt, style: .relative)
                            .foregroundStyle(.tertiary)
                        if notification.readAt == nil {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel("Unread")
                        }
                    }
                    Text(notification.branchNames.count == 1
                         ? "1 fully merged branch can be deleted"
                         : "\(notification.branchNames.count) fully merged branches can be deleted")
                        .foregroundStyle(.primary)
                    Label("Delete fully merged branches", systemImage: "trash")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Review and delete fully merged branches")
    }
}
