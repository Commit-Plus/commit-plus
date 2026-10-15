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

struct WelcomeRepositoryActivity: Identifiable, Codable, Equatable {
    var id: URL { url }
    let url: URL
    let name: String
    var commitsByDay: [Set<String>]
    var behindCount = 0
    var conflictCount = 0
    var activityNote: String?
    var statusNote: String?

    var commitCount: Int { commitsByDay.reduce(0) { $0 + $1.count } }
    var needsAttention: Bool {
        behindCount > 0 || conflictCount > 0 || activityNote != nil || statusNote != nil
    }
}
