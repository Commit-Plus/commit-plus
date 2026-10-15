// SPDX-License-Identifier: AGPL-3.0-or-later
import Charts
import SwiftUI

struct RepositoryStatisticsView: View {
    let repositoryURL: URL
    @State private var statistics: RepositoryStatistics?
    @State private var error: String?
    @State private var range = "All time"
    @State private var start = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
    @State private var end = Date.now
    @State private var loading = false
    @State private var usesTwoColumns = false
    @State private var showingContributors = false
    @State private var reloadGeneration = 0
    @State private var completedReloadGeneration = 0

    private var query: RepositoryStatisticsQuery {
        if range == "Custom" {
            return .init(start: Calendar.current.startOfDay(for: start), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)))
        }
        return .init(start: range == "Last year" ? Calendar.current.date(byAdding: .year, value: -1, to: Calendar.current.startOfDay(for: .now)) : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RepositoryStatisticsRangeCard(range: $range, start: $start, end: $end,
                                          total: statistics?.total, loading: loading,
                                          isShallow: statistics?.isShallow == true, error: error,
                                          onReload: { reloadGeneration += 1 })
            if let statistics {
                if statistics.total == 0 {
                    RepositoryDetailBlock {
                        ContentUnavailableView("No Commits", systemImage: "chart.bar", description: Text("No commits in this period."))
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: usesTwoColumns ? 2 : 1), alignment: .leading, spacing: 20) {
                        RepositoryDetailBlock {
                            Chart(statistics.monthly) { point in
                                LineMark(x: .value("Month", point.month), y: .value("Commits", point.count))
                                    .foregroundStyle(by: .value("Contributor", point.contributor))
                                    .symbol(by: .value("Contributor", point.contributor))
                            }
                            .chartOverlay { proxy in
                                RepositoryChartHoverOverlay(proxy: proxy) { proxy, point, size in
                                    guard let month: String = proxy.value(atX: point.x) else { return nil }
                                    let values = statistics.monthly.filter { $0.month == month }
                                    guard !values.isEmpty else { return nil }
                                    guard let x = proxy.position(forX: month) else { return nil }
                                    var highlight = Path()
                                    highlight.move(to: CGPoint(x: x, y: 0))
                                    highlight.addLine(to: CGPoint(x: x, y: size.height))
                                    for value in values {
                                        if let y = proxy.position(forY: value.count) {
                                            highlight.addEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                                        }
                                    }
                                    return RepositoryChartHoverInfo(text: ([month] + values.map { "\($0.contributor): \($0.count) commits" }).joined(separator: "\n"), highlight: highlight)
                                }
                            }
                            .frame(height: 260).padding(.vertical, 12)
                        } header: { Label("Commits per Month", systemImage: "chart.xyaxis.line") }
                        RepositoryDetailBlock {
                            Chart(topContributors(statistics)) { contributor in
                                SectorMark(angle: .value("Commits", contributor.count), innerRadius: .ratio(0.65), angularInset: 2)
                                    .foregroundStyle(by: .value("Contributor", contributor.key))
                            }
                            .chartOverlay { proxy in
                                RepositoryChartHoverOverlay(proxy: proxy) { _, point, size in
                                    let x = point.x - size.width / 2
                                    let y = point.y - size.height / 2
                                    let radius = min(size.width, size.height) / 2
                                    let distance = hypot(x, y)
                                    guard distance >= radius * 0.65, distance <= radius else { return nil }
                                    let angle = (atan2(x, -y) + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
                                    let value = angle / (2 * .pi) * Double(statistics.total)
                                    var cumulative = 0
                                    for contributor in topContributors(statistics) {
                                        let start = Double(cumulative) / Double(statistics.total) * 360 - 90
                                        cumulative += contributor.count
                                        if value < Double(cumulative) {
                                            let percent = Double(contributor.count) / Double(statistics.total)
                                            let end = Double(cumulative) / Double(statistics.total) * 360 - 90
                                            let center = CGPoint(x: size.width / 2, y: size.height / 2)
                                            var highlight = Path()
                                            highlight.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                                            highlight.addArc(center: center, radius: radius * 0.65, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
                                            highlight.closeSubpath()
                                            return RepositoryChartHoverInfo(text: "\(contributor.key)\n\(contributor.count) commits · \(percent.formatted(.percent.precision(.fractionLength(1))))", highlight: highlight)
                                        }
                                    }
                                    return nil
                                }
                            }
                            .frame(height: 260).padding(.vertical, 12)
                        } header: {
                            HStack {
                                Label("Contributors", systemImage: "person.2")
                                Spacer()
                                Button("All contributors (\(statistics.contributors.count))") { showingContributors = true }
                                    .buttonStyle(.link).font(.subheadline)
                            }
                        }
                        RepositoryDetailBlock {
                            Chart(statistics.weekdays) { value in
                                BarMark(x: .value("Weekday", value.key), y: .value("Commits", value.count))
                                    .foregroundStyle(.blue.gradient).cornerRadius(3)
                            }
                            .chartOverlay { proxy in
                                RepositoryChartHoverOverlay(proxy: proxy) { proxy, point, size in
                                    guard let day: String = proxy.value(atX: point.x),
                                          let value = statistics.weekdays.first(where: { $0.key == day }) else { return nil }
                                    guard let x = proxy.position(forX: day), let y = proxy.position(forY: value.count), let baseline = proxy.position(forY: 0) else { return nil }
                                    let width = size.width / CGFloat(max(statistics.weekdays.count, 1)) * 0.8
                                    return RepositoryChartHoverInfo(text: "\(day)\n\(value.count) commits", highlight: Path(roundedRect: CGRect(x: x - width / 2, y: y, width: width, height: max(2, baseline - y)), cornerRadius: 3))
                                }
                            }
                            .frame(height: 200).padding(.vertical, 12)
                        } header: { Label("Commits per Weekday", systemImage: "calendar") }
                        RepositoryDetailBlock {
                            Chart(statistics.hours) { value in
                                BarMark(x: .value("Hour", Int(value.key) ?? 0), y: .value("Commits", value.count))
                                    .foregroundStyle(.blue.gradient).cornerRadius(3)
                            }
                            .chartOverlay { proxy in
                                RepositoryChartHoverOverlay(proxy: proxy) { proxy, point, size in
                                    guard let hour: Double = proxy.value(atX: point.x),
                                          let value = statistics.hours.first(where: { Int($0.key) == Int(hour.rounded()) }) else { return nil }
                                    guard let x = proxy.position(forX: Int(value.key) ?? 0), let y = proxy.position(forY: value.count), let baseline = proxy.position(forY: 0) else { return nil }
                                    let width = size.width / 24 * 0.8
                                    return RepositoryChartHoverInfo(text: "\(value.key):00–\(value.key):59\n\(value.count) commits", highlight: Path(roundedRect: CGRect(x: x - width / 2, y: y, width: width, height: max(2, baseline - y)), cornerRadius: 3))
                                }
                            }
                            .frame(height: 200).padding(.vertical, 12)
                        } header: { Label("Commits per Hour", systemImage: "clock") }
                    }
                }
            }
        }
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.size.width >= 1200
        } action: { usesTwoColumns = $0 }
        .sheet(isPresented: $showingContributors) {
            RepositoryContributorsSheet(contributors: statistics?.contributors ?? [])
        }
        .task(id: "\(repositoryURL.path)|\(query)|\(reloadGeneration)") {
            await load(forceRefresh: reloadGeneration != completedReloadGeneration)
            if !Task.isCancelled { completedReloadGeneration = reloadGeneration }
        }
    }

    private func topContributors(_ statistics: RepositoryStatistics) -> [RepositoryStatistics.Count] {
        var result = Array(statistics.contributors.prefix(8))
        let other = statistics.contributors.dropFirst(8).reduce(0) { $0 + $1.count }
        if other > 0 { result.append(.init(key: "Other", count: other)) }
        return result
    }

    private func load(forceRefresh: Bool) async {
        loading = true
        do {
            let result = try await GitStatusService.shared.repositoryStatistics(in: repositoryURL, query: query, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }
            if result != statistics { statistics = result }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
        if !Task.isCancelled { loading = false }
    }
}
