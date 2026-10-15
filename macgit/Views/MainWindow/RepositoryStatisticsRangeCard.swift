// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryStatisticsRangeCard: View {
    @Binding var range: String
    @Binding var start: Date
    @Binding var end: Date
    let total: Int?
    let loading: Bool
    let isShallow: Bool
    let error: String?
    let onReload: () -> Void
    @State private var showingInformation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    title
                    period
                    Spacer(minLength: 12)
                    commits
                    information
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        title
                        Spacer(minLength: 8)
                        commits
                        information
                    }
                    period
                }
            }
            if range == "Custom" {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { fromDate; throughDate; Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 10) { fromDate; throughDate }
                }
            }
            HStack(alignment: .center, spacing: 12) {
                Text("Statistics are cached for 6 hours. Reload to update from local Git history.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(loading ? "Reloading…" : "Reload", systemImage: "arrow.clockwise", action: onReload)
                    .disabled(loading).fixedSize()
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            if isShallow {
                Label("Only locally available history is included in this shallow repository.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private var title: some View {
        Label("Date Range", systemImage: "calendar").font(.headline).fixedSize()
    }

    private var period: some View {
        Picker("Period", selection: $range) {
            Text("All time").tag("All time")
            Text("Last year").tag("Last year")
            Text("Custom").tag("Custom")
        }.labelsHidden().fixedSize()
    }

    private var commits: some View {
        HStack(spacing: 5) {
            if loading && total == nil { ProgressView().controlSize(.small) }
            else { Text(total.map { $0.formatted() } ?? "—").fontWeight(.semibold).monospacedDigit() }
            Text("commits").foregroundStyle(.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Commits in period")
        .accessibilityValue(loading ? "Loading" : total.map { $0.formatted() } ?? "—")
    }

    private var information: some View {
        Button("About these statistics", systemImage: "info.circle") { showingInformation.toggle() }
            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            .popover(isPresented: $showingInformation) {
                Text("History across all repository refs, including local branches, remotes, tags and HEAD. Shared commits are counted once, including merges. Contributor identity uses email. Times are shown in \(TimeZone.current.identifier).")
                    .font(.callout).padding(16).frame(width: 300, alignment: .leading)
            }
    }

    private var fromDate: some View {
        DatePicker("From", selection: $start, in: ...end, displayedComponents: .date).fixedSize()
    }

    private var throughDate: some View {
        DatePicker("Through", selection: $end, in: start..., displayedComponents: .date).fixedSize()
    }
}
