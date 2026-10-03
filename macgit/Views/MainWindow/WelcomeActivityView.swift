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

struct WelcomeActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTextScale) private var textScale
    let snapshot: WelcomeDashboardSnapshot
    let isLoading: Bool
    let onRepositoryOpened: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your commit activity").font(.title3.bold().scaled(by: textScale))
                    Text("Last 30 days · 7 most recent repositories")
                        .font(.caption.scaled(by: textScale)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                    .help("Computed entirely from local Git history")
            }
            if isLoading && snapshot.repositories.isEmpty {
                ProgressView("Reading local history…")
                    .font(.body.scaled(by: textScale))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if snapshot.repositories.isEmpty {
                ContentUnavailableView("Your activity starts here", systemImage: "square.grid.3x3",
                    description: Text("Open a repository to see your local commit activity."))
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                    WelcomeActivityGrid(snapshot: snapshot, onRepositoryOpened: onRepositoryOpened)
                        .padding(.vertical, 4)
                        .frame(minWidth: geometry.size.width, alignment: .center)
                    }
                }
                .frame(height: CGFloat(snapshot.repositories.count) * 16 + 40)
            }
            HStack(spacing: 5) {
                Text("Less")
                ForEach(0..<5) { level in
                    WelcomeActivityCell(count: level == 0 ? 0 : 1 << (level - 1))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                Spacer()
                Text("Local only").foregroundStyle(.secondary)
            }
            .font(.caption2.scaled(by: textScale))
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(colorScheme == .light ? 0.16 : 0.10)))
    }

}
