// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct PullRequestDetailWindowContent: View {
    @Environment(\.appTextScale) private var textScale
    @ObservedObject var controller: PullRequestController
    let selectedPullRequestID: Int
    let authorizeAction: () async -> Bool
    let onClose: () -> Void

    var body: some View {
        detailPanel
            .alert("Pull Request", isPresented: detailErrorPresented) {
                Button("OK", role: .cancel) {
                    controller.detailErrorMessage = nil
                    if controller.selectedDetail == nil { onClose() }
                }
            } message: {
                Text(controller.detailErrorMessage ?? "Could not load pull request details.")
            }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if controller.isLoadingDetail,
           controller.selectedDetail?.id != selectedPullRequestID {
            ProgressView("Loading pull request…")
                .font(.body.scaled(by: textScale))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = controller.selectedDetail,
                  detail.id == selectedPullRequestID {
            PullRequestDetailPane(
                detail: detail,
                onOpenPullRequest: {
                    Task {
                        guard await authorizeAction() else { return }
                        controller.openInBrowser(detail.summary)
                    }
                },
                isRefreshingDetail: controller.isLoadingDetail,
                onRefreshDetail: {
                    Task {
                        guard await authorizeAction() else { return }
                        await controller.loadPullRequestDetail(detail.summary, forceRefresh: true)
                    }
                },
                isSubmittingComment: controller.isPerformingAction,
                onSubmitComment: { body in
                    Task {
                        guard await authorizeAction() else { return }
                        await controller.comment(on: detail.summary, body: body)
                    }
                },
                changes: controller.selectedChanges,
                isLoadingChanges: controller.isLoadingChanges,
                changesErrorMessage: controller.changesErrorMessage,
                onLoadChanges: {
                    Task {
                        guard await authorizeAction() else { return }
                        await controller.loadPullRequestChanges(detail.summary)
                    }
                },
                onRefreshChanges: {
                    Task {
                        guard await authorizeAction() else { return }
                        await controller.loadPullRequestChanges(detail.summary, forceRefresh: true)
                    }
                },
                isMerging: controller.isPerformingAction,
                onMerge: {
                    Task {
                        guard await authorizeAction() else { return }
                        await controller.merge(detail.summary)
                    }
                }
            )
        } else if controller.detailErrorMessage != nil {
            ContentUnavailableView(
                "Could not load pull request",
                systemImage: "exclamationmark.triangle",
                description: Text("Close this window and select the pull request to try again.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView("Loading pull request…")
                .font(.body.scaled(by: textScale))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailErrorPresented: Binding<Bool> {
        Binding(
            get: { controller.detailErrorMessage != nil },
            set: { if !$0 { controller.detailErrorMessage = nil } }
        )
    }
}
