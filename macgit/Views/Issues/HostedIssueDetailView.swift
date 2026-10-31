// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// The selected issue's description and comments, with comment, close/reopen, and branch actions.
struct HostedIssueDetailView: View {
    static let minimumWidth: CGFloat = 300
    static let defaultWidth: CGFloat = 420
    static let maximumWidth: CGFloat = 720

    @Environment(\.appTextScale) private var textScale
    @ObservedObject var controller: HostedIssueController
    let provider: HostedIssueProvider
    let summary: HostedIssueSummary?
    let gitFlowEnabled: Bool
    let onOpenAccounts: () -> Void
    let onCreateBranch: (HostedIssueSummary, IssueBranchTarget) -> Void
    let onClose: () -> Void
    @State private var commentDraft = ""
    @State private var commentSelection: TextSelection?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let summary {
                        header(summary)
                    }
                    if let error = controller.writeError {
                        writeErrorBanner(error)
                    }
                    if controller.isLoadingDetail, controller.detail == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if let error = controller.detailError, controller.detail == nil {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else if let detail = controller.detail {
                        body(of: detail)
                        comments(of: detail)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            composer
        }
        .background(Color(nsColor: .textBackgroundColor))
        // Nothing inside the panel may draw over the issue list.
        .clipped()
    }

    // MARK: - Sections

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let summary {
                Menu {
                    HostedIssueActionsMenu(issue: summary, provider: provider, gitFlowEnabled: gitFlowEnabled) {
                        onCreateBranch(summary, $0)
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                stateButton(summary)
            } else {
                Spacer()
            }
            Button("Close Details", systemImage: "xmark", action: onClose)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func stateButton(_ summary: HostedIssueSummary) -> some View {
        let closing = summary.state == .open
        Button(closing ? "Close Issue" : "Reopen Issue", systemImage: closing ? "checkmark.circle" : "arrow.uturn.backward.circle") {
            Task { await controller.setState(closing ? .closed : .open) }
        }
        .disabled(controller.isWriting)
        .help(closing ? "Close this issue on the tracker" : "Reopen this issue on the tracker")
    }

    private func header(_ summary: HostedIssueSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.title)
                .font(.title3.weight(.semibold).scaled(by: textScale))
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text(provider.reference(for: summary.number))
                    .font(.callout.monospaced().scaled(by: textScale))
                    .foregroundStyle(.secondary)
                Text(summary.stateName ?? (summary.state == .open ? "Open" : "Closed"))
                    .font(.caption.weight(.medium).scaled(by: textScale))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((summary.state == .open ? Color.green : Color.purple).opacity(0.15), in: Capsule())
                    .foregroundStyle(summary.state == .open ? Color.green : Color.purple)
                if let type = summary.workItemType {
                    Text(type)
                        .font(.caption.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                }
            }
            metadataRow("Author", summary.author.map { [$0.displayName] } ?? [])
            metadataRow("Assignees", summary.assignees.map(\.displayName))
            if !summary.labels.isEmpty {
                HostedIssueLabelLayout(wraps: true) {
                    ForEach(summary.labels, id: \.self) { HostedIssueLabelChip(label: $0) }
                }
            }
            if let createdAt = summary.createdAt {
                Text("Created \(createdAt.formatted(date: .abbreviated, time: .shortened))"
                     + (summary.updatedAt.map { " · Updated \($0.formatted(.relative(presentation: .named)))" } ?? ""))
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func metadataRow(_ title: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            Text("\(title): \(values.joined(separator: ", "))")
                .font(.caption.scaled(by: textScale))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func body(of detail: HostedIssueDetail) -> some View {
        Divider()
        if detail.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No description.")
                .foregroundStyle(.secondary)
                .italic()
        } else {
            richText(detail.body, format: detail.bodyFormat)
        }
    }

    @ViewBuilder
    private func comments(of detail: HostedIssueDetail) -> some View {
        Divider()
        Text(detail.comments.isEmpty ? "No comments" : "\(detail.comments.count) comment\(detail.comments.count == 1 ? "" : "s")")
            .font(.headline.scaled(by: textScale))
        if detail.commentsUnavailable {
            Label("Comments could not be loaded.", systemImage: "exclamationmark.triangle")
                .font(.callout.scaled(by: textScale))
                .foregroundStyle(.secondary)
        }
        ForEach(detail.comments) { comment in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author?.displayName ?? "Unknown")
                        .font(.callout.weight(.semibold).scaled(by: textScale))
                    if let createdAt = comment.createdAt {
                        Text(createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption.scaled(by: textScale))
                            .foregroundStyle(.secondary)
                    }
                }
                richText(comment.body, format: comment.format)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func richText(_ text: String, format: HostedIssueTextFormat) -> some View {
        switch format {
        case .markdown:
            PullRequestMarkdownContent(content: text, baseURL: summary?.webURL ?? URL(string: "about:blank")!, textScale: textScale)
        case .html:
            // Azure HTML is shown as text so no remote content or script runs.
            Text(HostedIssueHTMLText.plainText(fromHTML: text))
                .font(.body.scaled(by: textScale))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func writeErrorBanner(_ error: HostedIssueError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.callout.scaled(by: textScale))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            switch error {
            case .missingScope, .reauthorizationRequired, .accountUpdateRequired:
                Button("Open Accounts…", action: onOpenAccounts)
                    .buttonStyle(.link)
            default:
                Button("Dismiss", action: controller.clearWriteError)
                    .buttonStyle(.link)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    /// One line by default, growing with the draft up to three lines before it scrolls.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment", text: $commentDraft, selection: $commentSelection, axis: .vertical)
                .lineLimit(1...3)
                // Shift-Return starts a new line, like chat apps; ⌘Return posts.
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    insertCommentNewline()
                    return .handled
                }
                .textFieldStyle(.plain)
                .font(.body.scaled(by: textScale))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            if controller.isWriting {
                ProgressView().controlSize(.small)
                    .padding(.bottom, 4)
            }
            Button("Comment", action: postComment)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canPostComment)
                .padding(.bottom, 2)
        }
        .padding(12)
    }

    /// Replaces the selection (or inserts at the caret) with a line break and keeps the caret after it.
    private func insertCommentNewline() {
        var range = commentDraft.endIndex..<commentDraft.endIndex
        if case .selection(let selected) = commentSelection?.indices {
            range = selected.clamped(to: commentDraft.startIndex..<commentDraft.endIndex)
        }
        let offset = commentDraft.distance(from: commentDraft.startIndex, to: range.lowerBound)
        commentDraft.replaceSubrange(range, with: "\n")
        commentSelection = TextSelection(insertionPoint: commentDraft.index(commentDraft.startIndex, offsetBy: offset + 1))
    }

    private var canPostComment: Bool {
        !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !controller.isWriting
    }

    private func postComment() {
        guard canPostComment else { return }
        Task {
            // The draft is kept when posting fails.
            if await controller.addComment(commentDraft) { commentDraft = "" }
        }
    }
}
