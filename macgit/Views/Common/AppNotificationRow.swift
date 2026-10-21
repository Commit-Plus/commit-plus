// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct AppNotificationRow: View {
    let notification: AppNotification
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: itemIcon.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(itemIcon.color)
                .frame(width: 28, height: 28)
                .background(itemIcon.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(notification.repositoryURL.lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    TimelineView(.everyMinute) { context in
                        Text(Self.relativeTime(from: notification.createdAt, now: context.date))
                            .fixedSize()
                    }
                    if notification.readAt == nil {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            .accessibilityLabel("Unread")
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                Button(action: onOpen) {
                    Text(message)
                        .font(.system(size: 13, weight: notification.readAt == nil ? .semibold : .regular))
                        .multilineTextAlignment(.leading).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(helpText)
                HStack(spacing: 8) {
                    Button(action: onOpen) {
                        Label {
                            Text(actionTitle).foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: actionIcon).foregroundStyle(itemIcon.color)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(helpText)
                    Spacer(minLength: 4)
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Delete notification")
                    .accessibilityLabel("Delete notification")
                }
            }
        }
        .padding(12)
        .background(isHovered ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(actionTitle, systemImage: actionIcon, action: onOpen)
            Button("Delete Notification", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    static func relativeTime(from date: Date, now: Date = .now) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hr ago" : "\(hours) hrs ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    private var itemIcon: (symbol: String, color: Color) {
        switch notification.kind {
        case .fullyMergedBranches: ("arrow.triangle.branch", .orange)
        case .pullRequestCreated: ("arrow.triangle.pull", .purple)
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
