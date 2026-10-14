// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ImageComparisonView: View {
    let request: ImageComparisonRequest
    let repositoryURL: URL
    let mode: ImageComparisonMode
    var refreshID: UUID? = nil
    @State private var before: NSImage?
    @State private var after: NSImage?
    @State private var beforeError: String?
    @State private var afterError: String?
    @State private var isLoading = true
    @State private var fraction = 0.5
    @State private var loadedRequest: LoadRequest?

    private struct LoadRequest: Hashable {
        let request: ImageComparisonRequest
        let repositoryURL: URL
    }

    private struct LoadID: Hashable {
        let request: ImageComparisonRequest
        let repositoryURL: URL
        let refreshID: UUID?
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading images…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if request.before == nil {
                ImageComparisonSide(title: nil, image: after, error: afterError,
                                    isMissing: request.after == nil)
            } else if mode == .overlay, let before, let after {
                VStack(spacing: 12) {
                    HStack {
                        Text("Before").foregroundStyle(.red)
                        Spacer()
                        Text("After").foregroundStyle(.green)
                    }.font(.caption.weight(.semibold))
                    ImagePreviewViewport {
                        ImageComparisonOverlay(before: before, after: after, fraction: $fraction)
                    }
                }.padding(12)
            } else {
                HStack(spacing: 0) {
                    ImageComparisonSide(title: "Before", image: before, error: beforeError,
                                        isMissing: request.before == nil)
                    Divider()
                    ImageComparisonSide(title: "After", image: after, error: afterError,
                                        isMissing: request.after == nil)
                }
            }
        }
        .task(id: LoadID(request: request, repositoryURL: repositoryURL, refreshID: refreshID)) {
            await load()
        }
    }

    private func load() async {
        let loadRequest = LoadRequest(request: request, repositoryURL: repositoryURL)
        let isNewRequest = loadedRequest != loadRequest
        if isNewRequest {
            isLoading = true
        }

        var loadedBefore: NSImage?
        var loadedAfter: NSImage?
        var loadedBeforeError: String?
        var loadedAfterError: String?
        for (isBefore, source) in [(true, request.before), (false, request.after)] {
            guard let source else { continue }
            do {
                let data = try await GitStatusService.shared.imageData(from: source, in: repositoryURL)
                try Task.checkCancellation()
                guard let image = NSImage(data: data) else {
                    throw GitError.commandFailed("This image format cannot be previewed, or its content is unavailable locally.")
                }
                if isBefore { loadedBefore = image } else { loadedAfter = image }
            } catch {
                guard !Task.isCancelled else { return }
                if isBefore {
                    loadedBeforeError = error.localizedDescription
                } else {
                    loadedAfterError = error.localizedDescription
                }
            }
        }
        guard !Task.isCancelled else { return }
        before = loadedBefore
        after = loadedAfter
        beforeError = loadedBeforeError
        afterError = loadedAfterError
        if isNewRequest {
            fraction = 0.5
        }
        loadedRequest = loadRequest
        isLoading = false
    }
}
