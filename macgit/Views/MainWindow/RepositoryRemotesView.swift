// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryRemotesView: View {
    let remotes: [RepositoryBookmarkRemote]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remotes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                ForEach(remotes) { remote in
                    GridRow {
                        HStack(spacing: 6) {
                            RepositoryProviderIcon(name: remote.identity.provider == .generic ? "code-branch" : remote.identity.provider.rawValue)
                                .frame(width: 18, height: 18)
                            Text(remote.name).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: 180, alignment: .leading).help(remote.name)
                        Link("Remote", destination: remote.webURL).help(remote.webURL.absoluteString)
                        if let issues = remote.issuesURL, let requests = remote.pullRequestsURL {
                            Link("Issues", destination: issues)
                            Link("Pull Requests", destination: requests)
                        }
                    }
                }
            }.buttonStyle(.link)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
