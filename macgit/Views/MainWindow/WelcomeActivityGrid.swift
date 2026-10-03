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

/// Explicit rows keep every repository's cells together, including repeated day IDs.
struct WelcomeActivityGrid: View {
    @Environment(\.appTextScale) private var textScale
    let snapshot: WelcomeDashboardSnapshot
    let onRepositoryOpened: (URL) -> Void

    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 4
    private let nameWidth: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: cellSpacing) {
            HStack(spacing: 12) {
                Text("Repository")
                    .frame(width: nameWidth, alignment: .leading)
                HStack(spacing: cellSpacing) {
                    ForEach(snapshot.days.indices, id: \.self) { index in
                        Color.clear
                            .frame(width: cellSize, height: 16)
                            .overlay(alignment: .leading) {
                                if index % 7 == 0 {
                                    Text(snapshot.days[index], format: .dateTime.month(.abbreviated).day())
                                        .fixedSize()
                                }
                            }
                    }
                }
                Text("Total").frame(width: 32, alignment: .trailing)
            }
            .font(.system(size: 10).scaled(by: textScale))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)

            ForEach(snapshot.repositories) { repository in
                HStack(spacing: 12) {
                    Button { onRepositoryOpened(repository.url) } label: {
                        Text(repository.name)
                            .font(.system(size: 10, weight: .medium).scaled(by: textScale))
                            .lineLimit(1)
                            .frame(width: nameWidth, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(repository.url.path)
                    HStack(spacing: cellSpacing) {
                        ForEach(snapshot.days.indices, id: \.self) { index in
                            let count = repository.commitsByDay[index].count
                            WelcomeActivityCell(count: count)
                                .frame(width: cellSize, height: cellSize)
                                .overlay {
                                    if repository.activityNote != nil && count == 0 {
                                        Text("–").font(.system(size: 8).scaled(by: textScale)).foregroundStyle(.secondary)
                                    }
                                }
                                .help(cellDescription(repository: repository, index: index))
                                .accessibilityLabel(cellDescription(repository: repository, index: index))
                        }
                    }
                    Text(repository.activityNote != nil && repository.commitCount == 0 ? "–" : "\(repository.commitCount)")
                        .font(.system(size: 10).monospacedDigit().scaled(by: textScale))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                .frame(height: cellSize)
            }
        }
    }

    private func cellDescription(repository: WelcomeRepositoryActivity, index: Int) -> String {
        "\(repository.name) · \(snapshot.days[index].formatted(date: .abbreviated, time: .omitted)): \(repository.commitsByDay[index].count) commits\(repository.activityNote.map { " · " + $0 } ?? "")"
    }

}
