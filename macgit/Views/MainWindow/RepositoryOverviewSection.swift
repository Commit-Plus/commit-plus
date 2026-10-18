// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryOverviewSection: View {
    let info: GitStatusService.RepositoryInfo?
    let size: Int64?
    let isLoading: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if let info {
                Label(info.branch ?? "Detached / empty", systemImage: "arrow.triangle.branch")
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                    .help(info.branch ?? "Detached / empty")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 14) {
                    metric("Changed files", value: info.changed.map(String.init) ?? "—")
                    metric("Commits", value: info.commits.map(String.init) ?? "—")
                        .help("Unique commits reachable from HEAD and all local refs, including branches, remotes and tags.")
                    metric("Repository size", value: size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .binary) } ?? "Calculating…")
                        .help("Size of the Git object database (loose objects and packs), in binary units. Working files and build caches are excluded. Linked worktrees share the same object database.")
                    metric("Initial commit", value: info.firstCommit?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        .help(info.firstCommit?.formatted() ?? "—")
                    metric("Last commit", value: info.lastCommit?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        .help(info.lastCommit?.formatted() ?? "—")
                }
                if !info.remotes.isEmpty {
                    Divider()
                    RepositoryRemotesView(remotes: info.remotes)
                }
            } else if isLoading {
                ProgressView("Reading repository information")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
