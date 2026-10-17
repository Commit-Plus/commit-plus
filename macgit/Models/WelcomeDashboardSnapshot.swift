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
import Foundation

struct WelcomeDashboardSnapshot: Equatable {
    let days: [Date]
    var repositories: [WelcomeRepositoryActivity] = []

    var dailyCommitCounts: [Int] {
        days.indices.map { index in
            repositories.reduce(into: Set<String>()) { hashes, repository in
                hashes.formUnion(repository.commitsByDay[index])
            }.count
        }
    }
    var commitCount: Int { dailyCommitCounts.reduce(0, +) }
    var activeDays: Int { dailyCommitCounts.filter { $0 > 0 }.count }
    var attentionCount: Int { repositories.filter(\.needsAttention).count }

    static func days(endingAt now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (-29...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
}
