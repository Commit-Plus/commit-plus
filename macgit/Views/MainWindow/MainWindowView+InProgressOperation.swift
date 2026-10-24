// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// A banner shown in the repository window's banner stack.
enum RepositoryBanner: Identifiable {
    case inProgressOperation(GitInProgressOperation)
    case appNotification(AppNotification)

    var id: String {
        switch self {
        case .inProgressOperation: "inProgressOperation"
        case .appNotification(let notification): "appNotification|\(notification.id)"
        }
    }
}

extension MainWindowView {
    /// Blocking repository state first, then announcements.
    var repositoryBanners: [RepositoryBanner] {
        var banners: [RepositoryBanner] = []
        if let operation = syncState.inProgressOperation {
            banners.append(.inProgressOperation(operation))
        }
        banners += appNotificationController.bannerNotifications(for: repositoryURL).map(RepositoryBanner.appNotification)
        return banners
    }

    @ViewBuilder
    func repositoryBannerView(_ banner: RepositoryBanner) -> some View {
        switch banner {
        case .inProgressOperation(let operation):
            InProgressOperationBanner(
                operation: operation,
                isEmpty: syncState.commitBadgeCount == 0,
                onContinue: { Task { await continueInProgressOperation(operation) } },
                onSkip: { Task { await skipInProgressOperation(operation) } },
                onAbort: { Task { await abortInProgressOperation(operation) } }
            )
        case .appNotification(let notification):
            BranchCleanupBanner(
                branchCount: notification.branchNames.count,
                onDelete: { appNotificationController.activate(notification) },
                onClose: { appNotificationController.dismiss(notification) }
            )
        }
    }

    func continueInProgressOperation(_ operation: GitInProgressOperation) async {
        if case .merge = operation {
            guard await authorizeProtectedBranchCommit() else { return }
        }
        await runInProgressOperationCommand {
            switch operation {
            case .merge:
                try await GitStatusService.shared.continueMerge(in: repositoryURL)
            case .cherryPick:
                try await GitStatusService.shared.continueCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.continueRevert(in: repositoryURL)
            case .rebase:
                try await GitStatusService.shared.resumeHistoryRebase("--continue", in: repositoryURL)
            }
        }
    }

    func skipInProgressOperation(_ operation: GitInProgressOperation) async {
        guard operation.canSkip else { return }
        await runInProgressOperationCommand {
            switch operation {
            case .merge:
                return
            case .cherryPick:
                try await GitStatusService.shared.skipCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.skipRevert(in: repositoryURL)
            case .rebase:
                try await GitStatusService.shared.resumeHistoryRebase("--skip", in: repositoryURL)
            }
        }
    }

    func abortInProgressOperation(_ operation: GitInProgressOperation) async {
        await runInProgressOperationCommand {
            switch operation {
            case .merge:
                try await GitStatusService.shared.abortMerge(in: repositoryURL)
            case .cherryPick:
                try await GitStatusService.shared.abortCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.abortRevert(in: repositoryURL)
            case .rebase:
                try await GitStatusService.shared.resumeHistoryRebase("--abort", in: repositoryURL)
            }
        }
    }

    private func runInProgressOperationCommand(_ command: () async throws -> Void) async {
        do {
            try await command()
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await syncState.refresh(repositoryURL: repositoryURL)
            // Conflicts can be written by the failed command; let open views reload them.
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
            syncState.errorMessage = error.localizedDescription
            syncState.showingError = true
        }
    }
}
