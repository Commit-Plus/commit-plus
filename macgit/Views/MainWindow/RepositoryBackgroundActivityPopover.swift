// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

enum RepositoryActivityPopoverTab: Hashable {
    case audit
    case background
}

/// Audit of this session's Git actions for the repository, and the window's background lane.
struct RepositoryBackgroundActivityPopover: View {
    @ObservedObject var operationProgress: RepositoryOperationProgress
    let repositoryURL: URL
    let isAutomaticFetching: Bool
    let onViewDetail: (RepositoryBackgroundActivityItem) -> Void
    @State private var tab: RepositoryActivityPopoverTab

    init(
        operationProgress: RepositoryOperationProgress,
        repositoryURL: URL,
        isAutomaticFetching: Bool,
        onViewDetail: @escaping (RepositoryBackgroundActivityItem) -> Void
    ) {
        self.operationProgress = operationProgress
        self.repositoryURL = repositoryURL
        self.isAutomaticFetching = isAutomaticFetching
        self.onViewDetail = onViewDetail
        let hasBackgroundActivity = isAutomaticFetching || !operationProgress.backgroundItems.isEmpty
        _tab = State(initialValue: hasBackgroundActivity ? .background : .audit)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Activity", selection: $tab) {
                Text("Audit").tag(RepositoryActivityPopoverTab.audit)
                Text("Background").tag(RepositoryActivityPopoverTab.background)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 10)
            Divider()
            switch tab {
            case .audit:
                RepositoryActionAuditView(repositoryURL: repositoryURL)
            case .background:
                RepositoryBackgroundActivityList(
                    operationProgress: operationProgress,
                    isAutomaticFetching: isAutomaticFetching,
                    onViewDetail: onViewDetail
                )
            }
        }
        // Report each tab's ideal size so the popover resizes to it; otherwise flexible
        // content keeps the larger Audit size after switching to Background.
        .fixedSize()
    }
}

private struct RepositoryBackgroundActivityList: View {
    @ObservedObject var operationProgress: RepositoryOperationProgress
    let isAutomaticFetching: Bool
    let onViewDetail: (RepositoryBackgroundActivityItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isAutomaticFetching {
                RepositoryAutomaticFetchRow()
                if !operationProgress.backgroundItems.isEmpty {
                    Divider().padding(.leading, 46).padding(.trailing, 18)
                }
            }
            if operationProgress.backgroundItems.isEmpty {
                if !isAutomaticFetching {
                    ContentUnavailableView(
                        "No Background Activity",
                        systemImage: "checkmark.circle",
                        description: Text("No background Git actions are running.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(operationProgress.backgroundItems) { item in
                            RepositoryBackgroundActivityRow(
                                item: item,
                                onViewDetail: { onViewDetail(item) },
                                onDismiss: { operationProgress.dismissBackgroundItem(id: item.id) }
                            )
                            if item.id != operationProgress.backgroundItems.last?.id {
                                Divider().padding(.leading, 46).padding(.trailing, 18)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 360)
    }
}

/// Transient row for an automatic fetch; it disappears when the fetch ends and never reports errors.
private struct RepositoryAutomaticFetchRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().controlSize(.small)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Fetching from remotes")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("Checking for remote changes…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct RepositoryBackgroundActivityRow: View {
    let item: RepositoryBackgroundActivityItem
    let onViewDetail: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            stateIcon
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                switch item.state {
                case .queued:
                    Text("Waiting…").font(.caption).foregroundStyle(.secondary)
                case .running:
                    Text("Running…").font(.caption).foregroundStyle(.secondary)
                case .failed(let summary, _):
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if case .failed = item.state {
                Button("View", action: onViewDetail)
                    .controlSize(.small)
                    .help("View the full error message")
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Dismiss")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}
