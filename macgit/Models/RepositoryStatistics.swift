// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct RepositoryStatistics: Codable, Equatable {
    struct Count: Codable, Equatable, Identifiable {
        var id: String { key }
        var key: String
        var count: Int
    }
    struct Monthly: Codable, Equatable, Identifiable {
        var id: String { month + contributor }
        var month: String
        var contributor: String
        var count: Int
    }
    var monthly: [Monthly] = []
    var contributors: [Count] = []
    var weekdays: [Count] = []
    var hours: [Count] = []
    var total = 0
    var isShallow = false
    var calculatedAt = Date.now
    var fingerprint = ""
}

struct RepositoryStatisticsQuery: Codable, Equatable, Hashable {
    var start: Date?
    var end: Date?
    var timeZone = TimeZone.current.identifier
    // v2: all refs and HEAD, unique commits including merges, author time/email.
    var version = 2
}
