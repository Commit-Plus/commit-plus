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

struct PullRequestDetailHeader: View {
    @Environment(\.appTextScale) private var textScale
    let summary: PullRequestSummary
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.title)
                    .font(.title2.scaled(by: textScale))
                    .bold()
                    .lineLimit(2)
                Text("#\(summary.number)")
                    .font(.title2.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("Close detail", systemImage: "xmark", action: onClose)
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Close pull request detail")
            }

            HStack(spacing: 8) {
                Label(stateTitle, systemImage: stateIcon)
                    .font(.subheadline.scaled(by: textScale))
                    .bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(stateColor, in: Capsule())

                PullRequestAuthorAvatar(author: summary.author)
                Text(summary.author.username)
                    .font(.subheadline.scaled(by: textScale))
                    .bold()
                Text("opened this pull request on \(summary.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 7) {
                Text(summary.source.ref)
                    .branchBadge(scale: textScale)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("into")
                Text(summary.target.ref)
                    .branchBadge(scale: textScale)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("From \(summary.source.ref) into \(summary.target.ref)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var stateTitle: String {
        switch summary.state {
        case .open: "Open"
        case .draft: "Draft"
        case .closed: "Closed"
        case .merged: "Merged"
        }
    }

    private var stateIcon: String {
        switch summary.state {
        case .open, .draft: "arrow.triangle.pull"
        case .closed: "xmark.circle"
        case .merged: "arrow.triangle.merge"
        }
    }

    private var stateColor: Color {
        switch summary.state {
        case .open: .green
        case .draft: .orange
        case .closed: .red
        case .merged: .purple
        }
    }
}

private extension View {
    func branchBadge(scale: CGFloat) -> some View {
        font(.subheadline.monospaced().scaled(by: scale))
            .foregroundStyle(.blue)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
}
