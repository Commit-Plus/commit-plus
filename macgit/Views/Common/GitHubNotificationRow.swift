// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitHubNotificationRow: View {
    let notification: GitHubNotification
    let account: GitProviderAccount
    let showAccount: Bool
    let onOpen: () -> Void
    let onRead: () -> Void
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
                    Text(notification.repository.fullName)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(notification.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .fixedSize()
                    if notification.unread {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            .accessibilityLabel("Unread")
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                Button(action: onOpen) {
                    Text(notification.subject.title)
                        .font(.system(size: 13, weight: notification.unread ? .semibold : .regular))
                        .multilineTextAlignment(.leading).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open on GitHub and mark as read")
                HStack(spacing: 8) {
                    Text(notification.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                        .lineLimit(1)
                    if showAccount { Text("· \(account.username)").lineLimit(1) }
                    Spacer(minLength: 4)
                    Button(action: onOpen) {
                        Label("View", systemImage: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
                    .help("Open on GitHub and mark as read")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(isHovered ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("View on GitHub", systemImage: "arrow.up.right", action: onOpen)
            if notification.unread { Button("Mark as read", systemImage: "envelope.open", action: onRead) }
        }
    }

    private var itemIcon: (symbol: String, color: Color) {
        switch notification.subject.type {
        case "PullRequest": ("arrow.triangle.pull", .purple)
        case "Issue": ("exclamationmark.circle", .green)
        case "Discussion": ("bubble.left.and.bubble.right", .blue)
        case "Commit": ("point.topleft.down.to.point.bottomright.curvepath", .orange)
        case "Release": ("tag", .pink)
        case "CheckSuite", "WorkflowRun": ("play.circle", .indigo)
        case "RepositoryVulnerabilityAlert", "RepositoryAdvisory", "SecurityAdvisory": ("shield.lefthalf.filled", .red)
        default: ("bell", .teal)
        }
    }

}
