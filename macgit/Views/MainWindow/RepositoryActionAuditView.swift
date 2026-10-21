// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import SwiftUI

/// Holds one page of audit summaries and the selected entry; the rest stays on disk.
@MainActor
final class RepositoryActionAuditViewModel: ObservableObject {
    @Published private(set) var summaries: [RepositoryActionAuditSummary] = []
    @Published private(set) var selectedEntry: RepositoryActionAuditEntry?
    @Published private(set) var hasLoaded = false
    @Published var selectedID: Int64? {
        didSet {
            guard selectedID != oldValue else { return }
            loadSelectedEntry()
        }
    }

    private let repositoryPath: String
    private let store: RepositoryActionAuditStore
    private var reloadTask: Task<Void, Never>?
    private var entryTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    init(repositoryURL: URL, store: RepositoryActionAuditStore = .shared) {
        repositoryPath = repositoryURL.standardizedFileURL.path
        self.store = store
    }

    func start() {
        guard cancellable == nil else { return }
        let repositoryPath = repositoryPath
        cancellable = NotificationCenter.default.publisher(for: .repositoryActionAuditDidRecord)
            .filter { ($0.userInfo?["repositoryPath"] as? String) == repositoryPath }
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
        reload()
    }

    func stop() {
        cancellable = nil
        reloadTask?.cancel()
        entryTask?.cancel()
    }

    private func reload() {
        reloadTask?.cancel()
        reloadTask = Task {
            let summaries = await store.summaries(repositoryPath: repositoryPath)
            guard !Task.isCancelled else { return }
            self.summaries = summaries
            hasLoaded = true
            // Keep the selection while it still exists; otherwise select the newest item.
            if let selectedID, summaries.contains(where: { $0.id == selectedID }) { return }
            selectedID = summaries.first?.id
        }
    }

    private func loadSelectedEntry() {
        entryTask?.cancel()
        guard let selectedID else {
            selectedEntry = nil
            return
        }
        entryTask = Task {
            let entry = await store.entry(id: selectedID)
            guard !Task.isCancelled else { return }
            selectedEntry = entry
        }
    }
}

struct RepositoryActionAuditView: View {
    @StateObject private var model: RepositoryActionAuditViewModel

    init(repositoryURL: URL) {
        _model = StateObject(wrappedValue: RepositoryActionAuditViewModel(repositoryURL: repositoryURL))
    }

    var body: some View {
        Group {
            if model.hasLoaded && model.summaries.isEmpty {
                ContentUnavailableView(
                    "No Git Actions Yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Git actions that change this repository during this session appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    List(model.summaries, selection: $model.selectedID) { summary in
                        RepositoryActionAuditRow(summary: summary)
                            .tag(summary.id)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .frame(width: 300)
                    Divider()
                    RepositoryActionAuditDetail(entry: model.selectedEntry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 860, height: 460)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct RepositoryActionAuditRow: View {
    let summary: RepositoryActionAuditSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if summary.status != .succeeded {
                    Image(systemName: summary.status == .cancelled ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(summary.status == .cancelled ? Color.secondary : Color.red)
                        .imageScale(.small)
                }
                Text(summary.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(summary.finishedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                Text(summary.summary)
                    .font(.caption)
                    .foregroundStyle(summary.status == .failed ? Color.red : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                RepositoryActionAuditOriginPill(origin: summary.origin)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct RepositoryActionAuditOriginPill: View {
    let origin: RepositoryActionAuditOrigin

    var body: some View {
        Text(origin.label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(origin == .user ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().fill((origin == .user ? Color.accentColor : Color.secondary).opacity(0.15))
            )
            .help(origin == .user ? "Started by you" : "Started automatically by Commit+")
    }
}

private struct RepositoryActionAuditDetail: View {
    let entry: RepositoryActionAuditEntry?

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    RepositoryActionAuditOriginPill(origin: entry.origin)
                    Spacer(minLength: 12)
                    Text(statusText(entry))
                        .foregroundStyle(entry.status == .failed ? Color.red : Color.secondary)
                    Text(entry.finishedAt, format: .dateTime.day().month().year().hour().minute().second())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .frame(height: 40)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("$ git \(entry.command)")
                            .fontWeight(.semibold)
                        if entry.output.isEmpty {
                            Text(entry.summary)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(entry.output)
                        }
                        if entry.isOutputTruncated {
                            Text("Output truncated at \(RepositoryActionAudit.outputByteLimit / 1024) KB.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
        } else {
            Color.clear
        }
    }

    private func statusText(_ entry: RepositoryActionAuditEntry) -> String {
        let duration = entry.duration.formatted(.number.precision(.fractionLength(entry.duration < 10 ? 1 : 0)))
        switch entry.status {
        case .succeeded: return "Succeeded in \(duration)s"
        case .failed: return "Failed after \(duration)s"
        case .cancelled: return "Cancelled"
        }
    }
}
