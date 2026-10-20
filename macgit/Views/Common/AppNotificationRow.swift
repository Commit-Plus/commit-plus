// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct AppNotificationRow: View {
    let notification: AppNotification
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
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
                    Text(message)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Label(actionTitle, systemImage: actionIcon)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var iconName: String {
        switch notification.kind {
        case .fullyMergedBranches: "arrow.triangle.branch"
        case .pullRequestCreated: "arrow.triangle.pull"
        }
    }

    private var message: String {
        switch notification.kind {
        case .fullyMergedBranches:
            notification.branchNames.count == 1
                ? "1 fully merged branch can be deleted"
                : "\(notification.branchNames.count) fully merged branches can be deleted"
        case .pullRequestCreated:
            if let pullRequest = notification.pullRequest {
                "Pull request #\(pullRequest.number) created: \(pullRequest.title)"
            } else {
                "Pull request created"
            }
        }
    }

    private var actionTitle: String {
        switch notification.kind {
        case .fullyMergedBranches: "Delete fully merged branches"
        case .pullRequestCreated: "Open pull request"
        }
    }

    private var actionIcon: String {
        switch notification.kind {
        case .fullyMergedBranches: "trash"
        case .pullRequestCreated: "arrow.up.forward.app"
        }
    }

    private var helpText: String {
        switch notification.kind {
        case .fullyMergedBranches: "Review and delete fully merged branches"
        case .pullRequestCreated: "Open pull request details"
        }
    }
}
