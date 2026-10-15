// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum RepositoryStatisticsAggregator {
    nonisolated static func aggregate(_ log: String, query: RepositoryStatisticsQuery) -> RepositoryStatistics {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: query.timeZone) ?? .current
        var monthly: [String: [String: Int]] = [:]
        var authors: [String: Int] = [:]
        var names: [String: String] = [:]
        var weekdays = Array(repeating: 0, count: 7)
        var hours = Array(repeating: 0, count: 24)
        var total = 0
        for line in log.split(separator: "\n") {
            if Task.isCancelled { break }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, let seconds = Double(fields[0]) else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            if let start = query.start, date < start { continue }
            if let end = query.end, date >= end { continue }
            let author = String(fields[2]).lowercased()
            names[author] = names[author] ?? String(fields[1])
            let components = calendar.dateComponents([.year, .month, .weekday, .hour], from: date)
            let month = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
            monthly[month, default: [:]][author, default: 0] += 1
            authors[author, default: 0] += 1
            weekdays[((components.weekday ?? 1) + 5) % 7] += 1
            hours[components.hour ?? 0] += 1
            total += 1
        }
        let ranked = authors.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let top = Set(ranked.prefix(8).map(\.key))
        func label(_ email: String) -> String {
            let name = names[email] ?? email
            return names.values.filter { $0 == name }.count > 1 ? "\(name) <\(email)>" : name
        }
        var result = RepositoryStatistics()
        result.total = total
        result.contributors = ranked.map { .init(key: label($0.key), count: $0.value) }
        // Include zero months/series so a gap never suggests continuous activity.
        let sortedMonths = monthly.keys.sorted()
        var months = sortedMonths
        if let first = sortedMonths.first, let last = sortedMonths.last {
            let pieces = first.split(separator: "-").compactMap { Int($0) }
            if pieces.count == 2, var date = calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: 1)) {
                months = []
                while months.count < 1200 {
                    let components = calendar.dateComponents([.year, .month], from: date)
                    let month = String(format: "%04d-%02d", components.year!, components.month!)
                    guard month <= last else { break }
                    months.append(month)
                    guard let next = calendar.date(byAdding: .month, value: 1, to: date) else { break }
                    date = next
                }
            }
        }
        let seriesNames = ranked.prefix(8).map { label($0.key) } + (ranked.count > 8 ? ["Other"] : [])
        result.monthly = months.flatMap { month in
            var series: [String: Int] = [:]
            for (author, count) in monthly[month] ?? [:] { series[top.contains(author) ? label(author) : "Other", default: 0] += count }
            return seriesNames.map { RepositoryStatistics.Monthly(month: month, contributor: $0, count: series[$0] ?? 0) }
        }
        result.weekdays = zip(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], weekdays).map { .init(key: $0.0, count: $0.1) }
        result.hours = hours.enumerated().map { .init(key: String($0.offset), count: $0.element) }
        return result
    }
}
