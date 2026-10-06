// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitHubNotificationPopover: View {
    @ObservedObject var controller: GitHubNotificationController
    let onConnect: () -> Void
    @State private var visibleLimit = 20

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill").foregroundStyle(.secondary)
                Text("Notifications").font(.system(size: 15, weight: .semibold))
                Spacer()
                if controller.isRefreshing { ProgressView().controlSize(.mini) }
                GitHubNotificationRefreshButton(controller: controller)
                    .buttonStyle(.borderless).controlSize(.small)
            }
            .frame(height: 24)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
            if controller.accounts.isEmpty {
                ContentUnavailableView {
                    Label("Connect GitHub", systemImage: "bell")
                } description: {
                    Text("Connect a GitHub account to view its notifications here.")
                } actions: {
                    Button("Connect GitHub", action: onConnect)
                }
            } else {
                HStack(spacing: 8) {
                    if let account = controller.selectedAccounts.first, controller.selectedAccountKey != "all" {
                        AsyncImage(url: account.avatarURL) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                        .fixedSize()
                    }
                    Picker("GitHub account", selection: $controller.selectedAccountKey) {
                        Text("All accounts").tag("all")
                        ForEach(controller.accounts) { account in
                            Text(account.username).tag(controller.key(account))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 240)
                    .help("Filter GitHub account")
                    Spacer()
                    Text("\(controller.selectedAccounts.reduce(0) { $0 + controller.unreadCount(for: $1) }) unread")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .help("Unread notifications in the latest 50 per account")
                }
                .frame(height: 28)
                .padding(.horizontal, 18).padding(.bottom, 12)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.selectedAccounts) { account in
                            if let error = controller.errors[controller.key(account)] {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(account.username).font(.caption.bold())
                                    Text(error).font(.caption).foregroundStyle(.secondary)
                                    Button("Manage connections", action: onConnect).font(.caption)
                                }.padding()
                            }
                        }
                        if rows.isEmpty {
                            Text(controller.isRefreshing ? "Fetching notifications…" : "No cached notifications")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(32)
                        }
                        ForEach(Array(rows.prefix(visibleLimit))) { row in
                            GitHubNotificationRow(notification: row.notification, account: row.account,
                                showAccount: controller.selectedAccountKey == "all",
                                onOpen: { controller.open(row.notification, account: row.account) },
                                onRead: { controller.update(row.notification, account: row.account, done: false) })
                            Divider().padding(.leading, 50).padding(.trailing, 12)
                        }
                        if rows.count > visibleLimit {
                            Button("Load more") { visibleLimit += 20 }
                                .frame(maxWidth: .infinity).padding(12)
                        }
                    }.padding(.horizontal, 6).padding(.vertical, 4)
                }
                .frame(minHeight: 0, maxHeight: .infinity)
                .clipped()
                Divider()
                HStack {
                    Text("GitHub").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Spacer()
                    if controller.selectedAccounts.count == 1, let account = controller.selectedAccounts.first {
                        Button { controller.openInbox(account: account) } label: {
                            Label("View more on GitHub", systemImage: "arrow.up.right")
                        }
                    } else {
                        Menu("View more on GitHub") {
                            ForEach(controller.selectedAccounts) { account in
                                Button("\(account.username) · \(GitProviderHost.identityKey(account.hostURL))") { controller.openInbox(account: account) }
                            }
                        }.menuStyle(.borderlessButton).fixedSize()
                    }
                }
                .frame(height: 20)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .help("Opens with the account signed into your browser")
            }
        }
        .font(.system(size: 13))
        .frame(width: 400, height: 520)
        .task { controller.opened() }
        .onChange(of: controller.selectedAccountKey) { _, _ in
            visibleLimit = 20
            controller.opened()
        }
    }

    private var rows: [GitHubNotificationDisplayRow] {
        controller.selectedAccounts.flatMap { account in
            (controller.caches[controller.key(account)]?.notifications ?? []).map {
                GitHubNotificationDisplayRow(id: controller.key(account) + ":" + $0.id, notification: $0, account: account)
            }
        }.sorted { $0.notification.updatedAt > $1.notification.updatedAt }
    }
}
