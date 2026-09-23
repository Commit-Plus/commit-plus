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

struct WelcomeDashboardContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let model: WelcomeDashboardModel
    let accountDisplayName: String?
    let repositoryCount: Int
    let onRefresh: () -> Void
    let onOpenAccount: () -> Void
    let onReviewAttention: (WelcomeRepositoryAttention) -> Void
    let onRepositoryOpened: (URL) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(accountDisplayName.map { "Welcome back, 👋 \($0)" } ?? "Welcome back")
                                .font(.largeTitle.bold())
                            Text("A little perspective on your local work.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                            .labelStyle(.iconOnly)
                            .disabled(model.isLoading)
                            .help("Refresh local dashboard data")
                        Button("Account", systemImage: "person.crop.circle", action: onOpenAccount)
                            .labelStyle(.iconOnly)
                            .help("Commit+ Account")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: geometry.size.width >= 780 ? 4 : 2), spacing: 12) {
                        WelcomeOverviewCard(title: "Repositories", value: "\(repositoryCount)", detail: "In your recent list", icon: "folder", tint: .blue)
                        WelcomeOverviewCard(title: "Your commits", value: model.isLoading ? "…" : "\(model.snapshot.commitCount)", detail: "Past 30 days · local", icon: "point.topleft.down.to.point.bottomright.curvepath", tint: .green)
                        WelcomeOverviewCard(title: "Active days", value: model.isLoading ? "…" : "\(model.snapshot.activeDays) / 30", detail: "Days with your commits", icon: "calendar", tint: .purple)
                        WelcomeOverviewCard(title: "Attention", value: model.isCheckingAttention ? "…" : "\(model.attention.count)", detail: "Repositories to review", icon: "bell", tint: .orange)
                    }
                    WelcomeActivityView(snapshot: model.snapshot, isLoading: model.isLoading, onRepositoryOpened: onRepositoryOpened)
                    WelcomeAttentionView(repositories: model.attention, isLoading: model.isCheckingAttention, hasRepositories: repositoryCount > 0, updatedAt: model.attentionUpdatedAt, onReview: onReviewAttention)
                    if let date = model.updatedAt {
                        Text("Updated \(date.formatted(date: .omitted, time: .shortened)) · Dashboard reads local Git only")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            .background(colorScheme == .light ? Color(red: 0.94, green: 0.95, blue: 0.97) : Color(nsColor: .windowBackgroundColor))
        }
    }
}
