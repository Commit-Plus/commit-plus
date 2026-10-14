// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct CreatePullRequestPreparationView: View {
    @ObservedObject var controller: PullRequestController
    @ObservedObject var windowController: CreatePullRequestWindowController
    let repositoryURL: URL
    let loadDraft: @MainActor () async throws -> PullRequestDraftSeed
    let authorizeAction: () async -> Bool
    let onGenerateText: PullRequestAIGenerationAction
    let onCancel: () -> Void
    let onCreate: (PullRequestDraft) async -> Void

    var body: some View {
        RepositorySheetLoadingView(title: "Create Pull Request", load: loadDraft,
                                   onCancel: onCancel, cancelRequestID: windowController.cancelRequestID) { seed in
            CreatePullRequestWindowContent(
                controller: controller, windowController: windowController,
                seed: seed, repositoryURL: repositoryURL,
                authorizeAction: authorizeAction, onGenerateText: onGenerateText,
                onCancel: onCancel, onCreate: onCreate
            )
        }
    }
}
