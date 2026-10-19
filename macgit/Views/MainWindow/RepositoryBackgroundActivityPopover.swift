// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryBackgroundActivityPopover: View {
    @ObservedObject var operationProgress: RepositoryOperationProgress
    let onViewDetail: (RepositoryBackgroundActivityItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                Text("Background Activity").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .frame(height: 24)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
            Divider()
            if operationProgress.backgroundItems.isEmpty {
                ContentUnavailableView(
                    "No Background Activity",
                    systemImage: "checkmark.circle",
                    description: Text("No background Git actions are running.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
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
