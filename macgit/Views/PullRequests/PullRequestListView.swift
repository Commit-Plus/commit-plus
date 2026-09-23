//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import MarkdownUI
import SwiftUI

struct PullRequestListView: View {
    @ObservedObject var controller: PullRequestController
    let repositoryURL: URL
    var accountConnectionErrorMessage: String? = nil
    var onReconnectAccount: () -> Void = {}
    var onRequestCreatePullRequest: () -> Void = {}
    var onSubmitCreatePullRequest: (PullRequestDraft) -> Void = { _ in }
    var onGenerateCreatePullRequestText: PullRequestAIGenerationAction = { _, _, _ in "" }
    var authorizeAction: () async -> Bool = { true }
    @State private var pendingCommentPullRequest: PullRequestSummary?
    @State private var selectedPullRequestID: Int?

    var body: some View {
        Group {
            if let seed = controller.createDraftSeed {
                CreatePullRequestView(
                    seed: seed,
                    repositoryURL: repositoryURL,
                    isSubmitting: controller.isPerformingAction,
                    changedFileCount: controller.createDraftChangedFileCount,
                    isLoadingChanges: controller.isLoadingCreateDraftChanges,
                    changesErrorMessage: controller.createDraftChangesErrorMessage,
                    participants: controller.createDraftParticipants,
                    isLoadingParticipants: controller.isLoadingCreateDraftParticipants,
                    participantsErrorMessage: controller.createDraftParticipantsErrorMessage,
                    loadSourceBranches: { query in
                        await controller.loadCreateDraftSourceBranches(query: query)
                    },
                    loadTargetBranches: { query in
                        await controller.loadCreateDraftTargetBranches(query: query)
                    },
                    onGenerateText: onGenerateCreatePullRequestText,
                    onCancel: { controller.dismissCreatePullRequest() },
                    onBranchesChanged: { sourceBranch, targetBranch in
                        Task {
                            guard await authorizeAction() else { return }
                            if let targetBranch {
                                await controller.loadCreateDraftChanges(
                                    sourceBranch: sourceBranch,
                                    targetBranch: targetBranch
                                )
                            } else {
                                controller.resetCreateDraftChanges()
                            }
                        }
                    },
                    onCreate: onSubmitCreatePullRequest
                )
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()

                    if controller.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = controller.errorMessage {
                        VStack(spacing: 12) {
                            Text(errorMessage)
                                .font(.headline)
                            if controller.needsAccountConnectionAction {
                                Text("Pull requests require an OAuth account over HTTPS. SSH keys are only used for Git fetch and push.")
                                    .font(.callout)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: 440)

                                HStack(spacing: 10) {
                                    Button(controller.accountConnectionActionTitle, action: onReconnectAccount)
                                    Button("Reload", systemImage: "arrow.clockwise") {
                                        Task {
                                            guard await authorizeAction() else { return }
                                            await controller.loadPullRequests(repositoryURL: repositoryURL, forceRefresh: true)
                                        }
                                    }
                                    .disabled(controller.isLoading)
                                }
                                if let accountConnectionErrorMessage {
                                    Text(accountConnectionErrorMessage)
                                        .font(.callout)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if controller.visibleItems.isEmpty {
                        Text(emptyStateMessage)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedPullRequestID != nil {
                        PersistentHSplit(
                            autosaveName: "PullRequestMainSplit",
                            left: {
                                pullRequestListPanel
                            },
                            right: {
                                detailPanel
                                    .frame(
                                        minWidth: 680,
                                        idealWidth: 820,
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .top
                                    )
                            }
                        )
                    } else {
                        pullRequestListPanel
                    }
                }
            }
        }
        .replacingSheet(item: $pendingCommentPullRequest) { pullRequest in
            PullRequestCommentSheet(
                pullRequest: pullRequest,
                isSubmitting: controller.isPerformingAction,
                onCancel: { pendingCommentPullRequest = nil },
                onSubmit: { body in
                    Task {
                        guard await authorizeAction() else { return }
                        await controller.comment(on: pullRequest, body: body)
                        if controller.detailErrorMessage == nil {
                            pendingCommentPullRequest = nil
                        }
                    }
                }
            )
        }
        .alert("Pull Request", isPresented: detailErrorPresented) {
            Button("OK", role: .cancel) {
                controller.detailErrorMessage = nil
            }
        } message: {
            Text(controller.detailErrorMessage ?? "Could not load pull request details.")
        }
        .task(id: repositoryURL) {
            guard await authorizeAction() else { return }
            closeDetail()
            await controller.loadPullRequests(repositoryURL: repositoryURL)
        }
        .onChange(of: controller.stateFilter) { _, _ in
            closeDetail()
            Task {
                guard await authorizeAction() else { return }
                await controller.loadPullRequests(repositoryURL: repositoryURL)
            }
        }
    }

    private var pullRequestListPanel: some View {
        VStack(spacing: 0) {
            List(controller.visibleItems) { item in
                PullRequestRow(
                    summary: item,
                    isBusy: controller.isPerformingAction,
                    onOpen: {
                        Task {
                            guard await authorizeAction() else { return }
                            controller.openInBrowser(item)
                        }
                    },
                    onCheckout: {
                        Task {
                            guard await authorizeAction() else { return }
                            await controller.checkout(item)
                        }
                    },
                    onComment: {
                        Task {
                            guard await authorizeAction() else { return }
                            pendingCommentPullRequest = item
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPullRequestID = item.id
                    controller.clearSelectedDetail()
                    Task {
                        guard await authorizeAction() else { return }
                        await controller.loadPullRequestDetail(item)
                    }
                }
                .listRowSeparator(.visible)
            }
            .listStyle(.plain)

            paginationFooter
        }
        .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity)
    }

    @ViewBuilder
    private var detailPanel: some View {
        if controller.isLoadingDetail,
           controller.selectedDetail?.id != selectedPullRequestID {
            ProgressView("Loading pull request…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = controller.selectedDetail,
                  detail.id == selectedPullRequestID {
            PullRequestDetailPane(
                detail: detail,
                onClose: closeDetail,
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
        } else {
            ProgressView("Loading pull request…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func closeDetail() {
        selectedPullRequestID = nil
        controller.clearSelectedDetail()
    }

    private var detailErrorPresented: Binding<Bool> {
        Binding(
            get: { controller.detailErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    controller.detailErrorMessage = nil
                }
            }
        )
    }

    private var header: some View {
        HStack {
            Text("Pull Requests")
                .font(.headline)
            Spacer()
            Picker("Filter", selection: $controller.stateFilter) {
                ForEach(PullRequestListFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            Toggle("Created by me", isOn: $controller.createdByMeOnly)
                .disabled(controller.selectedProviderAccountUsername == nil)
            Button("Create Pull Request", action: onRequestCreatePullRequest)
            .disabled(controller.isLoading || controller.errorMessage != nil)
            Button("Refresh pull requests", systemImage: "arrow.clockwise") {
                Task {
                    guard await authorizeAction() else { return }
                    await controller.loadPullRequests(repositoryURL: repositoryURL, forceRefresh: true)
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(controller.isLoading)
            .help("Refresh pull requests")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var paginationFooter: some View {
        HStack(spacing: 10) {
            Button("Previous page", systemImage: "chevron.left") {
                Task {
                    guard await authorizeAction() else { return }
                    await controller.loadPreviousPage(repositoryURL: repositoryURL)
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(controller.isLoading || !controller.hasPreviousPage)
            .help("Previous page")

            Text("Page \(controller.currentPage)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 54)

            Button("Next page", systemImage: "chevron.right") {
                Task {
                    guard await authorizeAction() else { return }
                    await controller.loadNextPage(repositoryURL: repositoryURL)
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(controller.isLoading || !controller.hasNextPage)
            .help("Next page")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var emptyStateMessage: String {
        switch controller.stateFilter {
        case .all:
            "No pull requests"
        case .open:
            "No open pull requests"
        case .closed:
            "No closed pull requests"
        }
    }
}

private struct PullRequestRow: View {
    let summary: PullRequestSummary
    let isBusy: Bool
    let onOpen: () -> Void
    let onCheckout: () -> Void
    let onComment: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("#\(summary.number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            Image(systemName: pullRequestIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(pullRequestTint)
                .frame(width: 18, height: 22)
                .help(pullRequestHelp)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    Image(systemName: combinedStatusIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(combinedStatusTint)
                        .help(combinedStatusHelp)
                }

                Text("\(summary.source.ref) -> \(summary.target.ref)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text("#\(summary.number) opened \(relativeString(for: summary.createdAt)) by \(summary.author.username)")
                    Text("updated \(relativeString(for: summary.updatedAt))")
                    if let mergedAt = summary.mergedAt {
                        Text("merged \(relativeString(for: mergedAt))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Checkout Pull Request", action: onCheckout)
                Button("Add Comment", action: onComment)
                Button("Open in Browser", action: onOpen)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .disabled(isBusy)

            Button("Open in browser", systemImage: "safari", action: onOpen)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Open in browser")
        }
        .padding(.vertical, 8)
    }

    private var pullRequestIcon: String {
        switch summary.state {
        case .open, .draft:
            "arrow.triangle.pull"
        case .closed:
            "xmark.circle"
        case .merged:
            "arrow.triangle.merge"
        }
    }

    private var pullRequestTint: Color {
        switch summary.state {
        case .open:
            .green
        case .draft:
            .orange
        case .closed:
            .red
        case .merged:
            .purple
        }
    }

    private var pullRequestHelp: String {
        switch summary.state {
        case .open:
            "Open pull request"
        case .draft:
            "Draft pull request"
        case .closed:
            "Closed pull request"
        case .merged:
            "Merged pull request"
        }
    }

    private var combinedStatusIcon: String {
        if summary.checkState == .success && summary.mergeReadiness == .ready {
            return "checkmark"
        }
        if summary.checkState == .failure || summary.checkState == .error || summary.mergeReadiness == .blocked {
            return "xmark"
        }
        switch summary.checkState {
        case .pending:
            return "clock"
        case .unknown, .noChecks, .success:
            return "questionmark"
        case .failure, .error:
            return "xmark"
        }
    }

    private var combinedStatusTint: Color {
        if summary.checkState == .success && summary.mergeReadiness == .ready {
            return .green
        }
        if summary.checkState == .failure || summary.checkState == .error || summary.mergeReadiness == .blocked {
            return .red
        }
        switch summary.checkState {
        case .pending:
            return .orange
        case .unknown, .noChecks, .success:
            return .secondary
        case .failure, .error:
            return .red
        }
    }

    private var combinedStatusHelp: String {
        "Checks: \(summary.checkState.rawValue). Merge: \(summary.mergeReadiness.rawValue)."
    }

    private func relativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct PullRequestDetailPane: View {
    let detail: PullRequestDetail
    let onClose: () -> Void
    let onOpenPullRequest: () -> Void
    let isRefreshingDetail: Bool
    let onRefreshDetail: () -> Void
    let isSubmittingComment: Bool
    let onSubmitComment: (String) -> Void
    let changes: [PullRequestChangedFile]
    let isLoadingChanges: Bool
    let changesErrorMessage: String?
    let onLoadChanges: () -> Void
    let onRefreshChanges: () -> Void
    let isMerging: Bool
    let onMerge: () -> Void
    @State private var selectedTab: PullRequestDetailTab = .overview
    @State private var isCommentBarExpanded = false
    @State private var isConfirmingMerge = false
    @State private var commentText = ""
    @FocusState private var isCommentFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PullRequestDetailHeader(summary: detail.summary, onClose: onClose)
            PullRequestDetailTabBar(selection: $selectedTab)

            if selectedTab == .overview {
                overviewContent
            } else {
                PullRequestChangesView(
                    files: changes,
                    isLoading: isLoadingChanges,
                    errorMessage: changesErrorMessage,
                    onRefresh: onRefreshChanges
                )
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isCommentBarExpanded) { _, isExpanded in
            if isExpanded {
                Task { @MainActor in
                    await Task.yield()
                    isCommentFocused = true
                }
            } else {
                isCommentFocused = false
            }
        }
        .onChange(of: detail.id) { _, _ in
            selectedTab = .overview
            isCommentBarExpanded = false
            commentText = ""
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .changes {
                onLoadChanges()
            }
        }
        .alert("Merge Pull Request?", isPresented: $isConfirmingMerge) {
            Button("Cancel", role: .cancel) {}
            Button("Merge Pull Request", action: onMerge)
        } message: {
            Text("Merge #\(detail.summary.number) into \(detail.summary.target.ref)? This updates the remote repository.")
        }
    }

    private var overviewContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        PullRequestConversationBlock(
                            author: detail.summary.author,
                            date: detail.summary.createdAt,
                            action: "opened this pull request"
                        ) {
                            if detail.body.isEmpty {
                                Text("No description provided.")
                                    .italic()
                                    .foregroundStyle(.secondary)
                            } else {
                                Markdown(detail.body)
                                    .markdownTheme(.gitHub)
                                    .textSelection(.enabled)
                            }
                        }

                        ForEach(detail.comments) { comment in
                            PullRequestConversationBlock(
                                author: comment.author,
                                date: comment.createdAt,
                                action: "commented"
                            ) {
                                Markdown(comment.body)
                                    .markdownTheme(.gitHub)
                                    .textSelection(.enabled)
                            }
                        }

                        if detail.comments.isEmpty {
                            Text("No comments yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        }

                        Button(action: onRefreshDetail) {
                            if isRefreshingDetail {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Refresh comments", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(isRefreshingDetail)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }

                commentComposer
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            PullRequestMetadataSidebar(
                reviewers: detail.reviewers,
                assignees: detail.assignees
            )
            .frame(width: 220)
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Button("Open PR", systemImage: "safari", action: onOpenPullRequest)
            Button("Merge Pull Request", systemImage: "arrow.triangle.merge") {
                isConfirmingMerge = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!canMerge || isMerging)
            .help(mergeButtonHelp)
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var canMerge: Bool {
        detail.summary.state == .open && detail.summary.mergeReadiness != .blocked
    }

    private var mergeButtonHelp: String {
        if detail.summary.state != .open {
            return "Only open pull requests can be merged."
        }
        if detail.summary.mergeReadiness == .blocked {
            return "This pull request is currently blocked from merging."
        }
        return "Merge this pull request into \(detail.summary.target.ref)."
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCommentBarExpanded {
                expandedCommentComposer
            } else {
                collapsedCommentComposer
            }
        }
        .background(.regularMaterial)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var collapsedCommentComposer: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                TextField("Add a comment", text: $commentText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .disabled(true)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCommentBarExpanded = true
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var expandedCommentComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                Text("Comment on #\(detail.summary.number)")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()
            }

            TextEditor(text: $commentText)
                .focused($isCommentFocused)
                .font(.system(size: 13))
                .lineSpacing(2)
                .frame(minHeight: 48, maxHeight: 100)
                .padding(6)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.separator.opacity(0.45), lineWidth: 0.5)
                }

            HStack {
                Spacer()

                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCommentBarExpanded = false
                    }
                }
                .buttonStyle(.borderless)

                Button("Add Comment") {
                    let body = commentText
                    commentText = ""
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCommentBarExpanded = false
                    }
                    onSubmitComment(body)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    isSubmittingComment
                        || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct FlowRow<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        HStack {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
