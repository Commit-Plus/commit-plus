// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Repository name in the window header. The provider icon doubles as the indicator for
/// this window's background Git activity, and clicking opens the activity popover.
struct RepositoryActivityHeaderButton: View {
    @ObservedObject var operationProgress: RepositoryOperationProgress
    let repositoryName: String
    let providerIconName: String
    let textScale: CGFloat
    let onViewErrorDetail: (RepositoryBackgroundActivityItem) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                indicator
                    .frame(width: 18, height: 18)
                Text(repositoryName)
                    .font(.headline.scaled(by: textScale))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel("\(repositoryName), \(helpText)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            RepositoryBackgroundActivityPopover(operationProgress: operationProgress) { item in
                isPresented = false
                onViewErrorDetail(item)
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch operationProgress.backgroundIndicator {
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
        switch operationProgress.backgroundIndicator {
        case .idle: "Background Git activity"
        case .running: "Background Git actions running"
        case .failed: "A background Git action failed"
        }
    }
}
