// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositorySummarySection: View {
    let summary: GitStatusService.RepositorySummary?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let summary {
                block("Recent Branches", systemImage: "arrow.triangle.branch", tint: .blue, items: summary.branches,
                      itemImage: { $0.isRemote ? "cloud" : "arrow.triangle.branch" }, empty: "No branches")
                block("Recent Tags", systemImage: "tag", tint: .orange, items: summary.tags, itemImage: { _ in "tag" }, empty: "No tags")
                block("Recent Commits", systemImage: "clock", tint: .purple, items: summary.commits,
                      itemImage: { _ in "smallcircle.filled.circle" }, monospacedName: true, empty: "No commits")
            } else if isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 200)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block(_ title: String, systemImage: String, tint: Color, items: [GitStatusService.RepositorySummaryItem],
                       itemImage: @escaping (GitStatusService.RepositorySummaryItem) -> String, monospacedName: Bool = false,
                       empty: String) -> some View {
        RepositoryDetailBlock {
            if items.isEmpty {
                Text(empty).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        GridRow {
                            Image(systemName: itemImage(item)).foregroundStyle(tint).frame(width: 16)
                                .help(item.isRemote ? "Remote branch" : "")
                            Text(item.name)
                                .font(monospacedName ? .body.monospaced() : .body)
                                .lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: 240, alignment: .leading)
                                .help(item.name)
                            Text(item.subject).foregroundStyle(.secondary).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(item.subject)
                            HStack(spacing: 6) {
                                ReflogActorAvatar(name: item.author, email: item.email, size: 18)
                                Text(item.author).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: 180, alignment: .leading)
                            .help(item.email.isEmpty ? item.author : "\(item.author) <\(item.email)>")
                            Group {
                                if let date = item.date {
                                    Text(date, format: .relative(presentation: .named)).help(date.formatted())
                                } else { Text("—") }
                            }
                            .foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                            .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        } header: {
            Label { Text(title) } icon: { Image(systemName: systemImage).foregroundStyle(tint) }
        }
    }
}
