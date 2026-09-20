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

struct HistoryCommitMessageCell: View {
    private static let emptyMessagePlaceholder = "<empty message>"

    let commit: Commit
    let graphModel: CommitGraphModel
    let isDragActive: Bool
    let scrollCoordinator: HistoryTableScrollCoordinator
    let onAppear: () -> Void

    private var displayMessage: String {
        let trimmedMessage = commit.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedMessage.isEmpty ? Self.emptyMessagePlaceholder : commit.message
    }

    var body: some View {
        HStack(spacing: 4) {
            if !commit.refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(commit.refs.prefix(3), id: \.self) { ref in
                        RefLabel(
                            text: ref,
                            graphColorIndex: graphModel.commitMetadata[commit.hash]?.colorIndex
                        )
                    }

                    if commit.refs.count > 3 {
                        Text("+\(commit.refs.count - 3)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(commit.refs.dropFirst(3).joined(separator: "\n"))
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Text(displayMessage)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(displayMessage)
        }
        .frame(height: 16)
        .opacity(isDragActive ? 0.4 : 1)
        .background {
            HistoryTableIntrospectionView(
                coordinator: scrollCoordinator
            )
        }
        .onAppear(perform: onAppear)
    }
}
