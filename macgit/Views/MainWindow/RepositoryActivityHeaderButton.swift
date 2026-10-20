// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Repository name in the window header. The provider icon doubles as the indicator for
/// this window's background Git activity, and clicking opens the activity popover.
struct RepositoryActivityHeaderButton: View {
    @ObservedObject var operationProgress: RepositoryOperationProgress
    let repositoryName: String
    let providerIconName: String
    let textScale: CGFloat
    let syncActivity: RepositorySyncActivity?
    let lastFetchSucceeded: Bool?
    /// Automatic remote fetches (app activation, initial load, interval) only drive the
    /// spinner and a transient popover row; they never enter the background lane.
    let isAutomaticFetching: Bool
    let onViewErrorDetail: (RepositoryBackgroundActivityItem) -> Void
    @State private var isPresented = false
    /// What finished last; nil until something has run in this window.
    @State private var idleStatus: String?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                indicator
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(repositoryName)
                        .font(.headline.scaled(by: textScale))
                    // A space keeps the line's height so the header does not jump.
                    Text(statusText ?? " ")
                        .font(.caption2.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel("\(repositoryName), \(statusText ?? helpText)")
        .onChange(of: activeStatus) { previousStatus, currentStatus in
            guard currentStatus == nil, let previousStatus else { return }
            idleStatus = completionText(after: previousStatus)
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            RepositoryBackgroundActivityPopover(
                operationProgress: operationProgress,
                isAutomaticFetching: isAutomaticFetching
            ) { item in
                isPresented = false
                onViewErrorDetail(item)
            }
        }
    }

    private var indicatorState: RepositoryBackgroundActivityIndicator {
        isAutomaticFetching ? .running : operationProgress.backgroundIndicator
    }

    /// Work currently shown in the header. Lane items and progress operations carry only a
    /// free-form title, so they show a generic short label instead of a verb guessed from it.
    private enum ActiveStatus: Equatable {
        case automaticFetch
        case sync(RepositorySyncActivity)
        case operation
        case cancelling
    }

    private var statusText: String? {
        if indicatorState == .failed { return "Failed" }
        guard let activeStatus else { return idleStatus }
        switch activeStatus {
        case .automaticFetch: return RepositorySyncActivity.fetching.label
        case .sync(let activity): return activity.label
        case .operation: return "Working"
        case .cancelling: return "Cancelling"
        }
    }

    private var activeStatus: ActiveStatus? {
        if isAutomaticFetching { return .automaticFetch }
        if let item = operationProgress.backgroundItems.first(where: \.isPending) {
            return .operation
        }
        if let operation = operationProgress.activeOperation {
            return operation.isCancelling ? .cancelling : .operation
        }
        return syncActivity.map(ActiveStatus.sync)
    }

    private func completionText(after status: ActiveStatus) -> String? {
        switch status {
        case .automaticFetch, .sync(.fetching):
            lastFetchSucceeded == false ? "Fetch failed" : "Fetched"
        case .cancelling:
            "Cancelled"
        case .sync, .operation:
            // Mutations refresh repository state through SyncState when they finish.
            "Reloaded"
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch indicatorState {
        case .idle:
            Image(providerIconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.red)
        }
    }

    private var helpText: String {
        switch indicatorState {
        case .idle: "Background Git activity"
        case .running where !operationProgress.hasPendingBackgroundWork: "Fetching from remotes"
        case .running: "Background Git actions running"
        case .failed: "A background Git action failed"
        }
    }
}
