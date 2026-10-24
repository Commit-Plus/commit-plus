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

import SwiftUI

struct PullRequestAIDraftContent: Equatable, Sendable {
    let title: String
    let description: String
}

extension PullRequestAIDraftContent {
    private static let sectionHeadings: Set<String> = [
        "summary", "description", "changes", "overview", "details", "motivation"
    ]

    /// Splits a model response into a title and description, tolerating code fences,
    /// "Title:"/"Description:" labels, a leading preamble line, and Markdown headings.
    init(generatedResponse: String) {
        var lines = generatedResponse
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")

        // A preamble such as "Here is the pull request:" followed by more text.
        if let first = lines.first?.trimmingCharacters(in: .whitespaces),
           first.hasSuffix(":"),
           Self.removingLabel("title", from: first) == nil,
           lines.count > 1 {
            lines.removeFirst()
            Self.dropLeadingBlankLines(&lines)
        }

        if lines.first?.hasPrefix("```") == true {
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
                lines.removeLast()
            }
        }
        Self.dropLeadingBlankLines(&lines)

        guard let firstLine = lines.first else {
            self.init(title: "", description: "")
            return
        }

        var candidate = firstLine.trimmingCharacters(in: .whitespaces)
        candidate = Self.removingLabel("title", from: candidate) ?? candidate
        candidate = candidate.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "*_`\"'“”‘’ "))

        let normalizedCandidate = candidate.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        if Self.sectionHeadings.contains(normalizedCandidate) {
            // The response opened with a description section; there is no usable title.
            self.init(title: "", description: Self.description(from: lines))
            return
        }

        lines.removeFirst()
        self.init(title: candidate, description: Self.description(from: lines))
    }

    private static func description(from lines: [String]) -> String {
        var lines = lines
        dropLeadingBlankLines(&lines)
        if let first = lines.first, let remainder = removingLabel("description", from: first) {
            lines[0] = remainder
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the text after a `Label:` prefix (optionally bold), or nil when the line has no such label.
    private static func removingLabel(_ label: String, from line: String) -> String? {
        let stripped = line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_"))
        guard stripped.lowercased().hasPrefix(label + ":") else { return nil }
        return String(stripped.dropFirst(label.count + 1))
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_ "))
    }

    private static func dropLeadingBlankLines(_ lines: inout [String]) {
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
    }
}

typealias PullRequestAIGenerationAction = @MainActor (
    String,
    String
) async throws -> PullRequestAIDraftContent

struct CreatePullRequestView: View {
    let seed: PullRequestDraftSeed
    let repositoryURL: URL
    let isSubmitting: Bool
    let changedFileCount: Int?
    let isLoadingChanges: Bool
    let changesErrorMessage: String?
    let participants: [PullRequestParticipant]
    let isLoadingParticipants: Bool
    let participantsErrorMessage: String?
    let loadSourceBranches: (String) async -> [String]
    let loadTargetBranches: (String) async -> [String]
    let onGenerateText: PullRequestAIGenerationAction
    var onCancel: () -> Void
    var onBranchesChanged: (String, String?) -> Void
    var onCreate: (PullRequestDraft) -> Void
    var isPresentedInWindow: Bool = false
    var cancelRequestID: UUID?

    @State private var sourceBranch: String
    @State private var targetBranch: String?
    @State private var title: String
    @State private var bodyText: String = ""
    @State private var selectedReviewerIDs: Set<String> = []
    @State private var selectedAssigneeIDs: Set<String> = []
    @State private var validationMessage: String?
    @State private var showingDiscardConfirmation = false
    @State private var isGeneratingDraft = false
    @State private var showingReplaceDraftConfirmation = false
    @State private var generationErrorMessage: String?

    init(
        seed: PullRequestDraftSeed,
        repositoryURL: URL,
        isSubmitting: Bool,
        changedFileCount: Int?,
        isLoadingChanges: Bool,
        changesErrorMessage: String?,
        participants: [PullRequestParticipant],
        isLoadingParticipants: Bool,
        participantsErrorMessage: String?,
        loadSourceBranches: @escaping (String) async -> [String],
        loadTargetBranches: @escaping (String) async -> [String],
        onGenerateText: @escaping PullRequestAIGenerationAction,
        onCancel: @escaping () -> Void,
        onBranchesChanged: @escaping (String, String?) -> Void,
        onCreate: @escaping (PullRequestDraft) -> Void,
        isPresentedInWindow: Bool = false,
        cancelRequestID: UUID? = nil
    ) {
        self.seed = seed
        self.repositoryURL = repositoryURL
        self.isSubmitting = isSubmitting
        self.changedFileCount = changedFileCount
        self.isLoadingChanges = isLoadingChanges
        self.changesErrorMessage = changesErrorMessage
        self.participants = participants
        self.isLoadingParticipants = isLoadingParticipants
        self.participantsErrorMessage = participantsErrorMessage
        self.loadSourceBranches = loadSourceBranches
        self.loadTargetBranches = loadTargetBranches
        self.onGenerateText = onGenerateText
        self.onCancel = onCancel
        self.onBranchesChanged = onBranchesChanged
        self.onCreate = onCreate
        self.isPresentedInWindow = isPresentedInWindow
        self.cancelRequestID = cancelRequestID
        _sourceBranch = State(initialValue: seed.sourceBranch)
        _targetBranch = State(initialValue: seed.targetBranch)
        _title = State(initialValue: seed.suggestedTitle)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PersistentHSplit(
                autosaveName: "CreatePullRequestMainSplit",
                left: {
                    formPanel
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
                },
                right: {
                    PullRequestDraftChangesView(
                        repositoryURL: repositoryURL,
                        remoteName: seed.remoteName,
                        sourceBranch: sourceBranch,
                        targetBranch: targetBranch
                    )
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                }
            )
        }
        .onAppear {
            reloadChanges()
        }
        .onChange(of: sourceBranch) { _, _ in
            reloadChanges()
        }
        .onChange(of: targetBranch) { _, _ in
            reloadChanges()
        }
        .onChange(of: cancelRequestID) { _, _ in
            requestCancel()
        }
        .confirmationDialog(
            "Discard Pull Request Draft?",
            isPresented: $showingDiscardConfirmation
        ) {
            Button("Discard Draft", role: .destructive, action: onCancel)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your title, description, and selections will be lost.")
        }
        .confirmationDialog(
            "Replace Title and Description?",
            isPresented: $showingReplaceDraftConfirmation
        ) {
            Button("Replace") {
                Task { @MainActor in
                    await generateDraft()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The generated text will replace the title and description you have written.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if !isPresentedInWindow {
                Button("Back to Pull Requests", systemImage: "chevron.left", action: requestCancel)
                    .buttonStyle(.borderless)
            }
            Text("Create Pull Request")
                .font(.headline)
            Spacer()
            Button("Cancel", action: requestCancel)
                .keyboardShortcut(.cancelAction)
            Button("Create Pull Request") {
                submit()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSubmitting || !canSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var formPanel: some View {
        GeometryReader { geometry in
            formContents(descriptionHeight: max(200, geometry.size.height * 0.55))
        }
    }

    private func formContents(descriptionHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SearchableBranchPicker(
                    title: "Source",
                    selection: Binding<String?>(
                        get: { sourceBranch },
                        set: { if let branch = $0 { sourceBranch = branch } }
                    ),
                    placeholder: "Search source branches",
                    noneTitle: "None",
                    allowsNone: false,
                    loadBranches: loadSourceBranches
                )

                SearchableBranchPicker(
                    title: "Target",
                    selection: $targetBranch,
                    placeholder: "Search target branches",
                    noneTitle: "None",
                    allowsNone: true,
                    loadBranches: loadTargetBranches
                )

                changeSummary

                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Pull request title", text: $title)
                            .textFieldStyle(.roundedBorder)
                        generateButton
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PullRequestDescriptionEditor(text: $bodyText)
                        .frame(height: descriptionHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        }
                }

                if let generationErrorMessage {
                    Label(generationErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if seed.repository.provider.supportsPullRequestParticipants {
                    PullRequestParticipantPicker(
                        title: "Reviewers",
                        participants: participants,
                        selectedIDs: $selectedReviewerIDs,
                        isLoading: isLoadingParticipants
                    )

                    PullRequestParticipantPicker(
                        title: "Assignees",
                        participants: participants,
                        selectedIDs: $selectedAssigneeIDs,
                        isLoading: isLoadingParticipants
                    )
                }

                if let participantsErrorMessage {
                    Label(participantsErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && targetBranch != nil
            && sourceBranch != targetBranch
            && changedFileCount.map { $0 > 0 } == true
            && !isLoadingChanges
    }

    private var canGenerateText: Bool {
        targetBranch != nil
            && sourceBranch != targetBranch
            && changedFileCount.map { $0 > 0 } == true
            && !isLoadingChanges
            && !isSubmitting
            && !isGeneratingDraft
    }

    private var generateButton: some View {
        Button {
            if hasEditedTitleOrDescription {
                showingReplaceDraftConfirmation = true
            } else {
                Task { @MainActor in
                    await generateDraft()
                }
            }
        } label: {
            ZStack {
                Label("Generate pull request title and description", systemImage: "sparkles")
                    .labelStyle(.iconOnly)
                    .opacity(isGeneratingDraft ? 0 : 1)
                if isGeneratingDraft {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
        .disabled(!canGenerateText)
        .help(generateHelp)
        .accessibilityLabel(isGeneratingDraft
            ? "Generating pull request title and description"
            : "Generate pull request title and description")
        .onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }

    private var generateHelp: String {
        guard targetBranch != nil, sourceBranch != targetBranch else {
            return "Select different source and target branches first."
        }
        guard changedFileCount.map({ $0 > 0 }) == true else {
            return "Pull request changes must be available before generating text."
        }
        return "Generate an editable title and description from the pull request changes."
    }

    private var hasEditedTitleOrDescription: Bool {
        let editedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!editedTitle.isEmpty && title != seed.suggestedTitle)
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func generateDraft() async {
        guard let targetBranch, canGenerateText else { return }
        let requestedSourceBranch = sourceBranch
        generationErrorMessage = nil
        isGeneratingDraft = true
        defer { isGeneratingDraft = false }
        do {
            let generated = try await onGenerateText(requestedSourceBranch, targetBranch)
            // Drop results for a branch comparison the user has since changed.
            guard sourceBranch == requestedSourceBranch, self.targetBranch == targetBranch else { return }
            if !generated.title.isEmpty {
                title = generated.title
            }
            if !generated.description.isEmpty {
                bodyText = generated.description
            }
        } catch {
            generationErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var changeSummary: some View {
        HStack(spacing: 8) {
            if isLoadingChanges {
                ProgressView()
                    .controlSize(.small)
                Text("Checking file changes...")
            } else if let changesErrorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(changesErrorMessage)
                    .foregroundStyle(.secondary)
            } else if let changedFileCount {
                Image(systemName: changedFileCount > 0 ? "doc.on.doc" : "exclamationmark.circle")
                    .foregroundStyle(changedFileCount > 0 ? Color.secondary : Color.orange)
                    .accessibilityHidden(true)
                Text(changedFileCount == 1 ? "1 file changed" : "\(changedFileCount) files changed")
                    .foregroundStyle(changedFileCount > 0 ? .primary : .secondary)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func reloadChanges() {
        validationMessage = nil
        onBranchesChanged(sourceBranch, targetBranch)
    }

    private func requestCancel() {
        guard !isSubmitting else { return }
        if hasDraftChanges {
            showingDiscardConfirmation = true
        } else {
            onCancel()
        }
    }

    private var hasDraftChanges: Bool {
        sourceBranch != seed.sourceBranch
            || targetBranch != seed.targetBranch
            || title != seed.suggestedTitle
            || !bodyText.isEmpty
            || !selectedReviewerIDs.isEmpty
            || !selectedAssigneeIDs.isEmpty
    }

    private func submit() {
        guard let targetBranch else {
            validationMessage = "Please select a target branch."
            return
        }
        do {
            let draft = try PullRequestDraft(
                repository: seed.repository,
                sourceBranch: sourceBranch,
                targetBranch: targetBranch,
                title: title,
                body: bodyText,
                reviewers: participants.filter { selectedReviewerIDs.contains($0.id) },
                assignees: participants.filter { selectedAssigneeIDs.contains($0.id) }
            )
            validationMessage = nil
            onCreate(draft)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct PullRequestCommentSheet: View {
    let pullRequest: PullRequestSummary
    let isSubmitting: Bool
    var onCancel: () -> Void
    var onSubmit: (String) -> Void

    @State private var bodyText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Comment on #\(pullRequest.number)")
                .font(.title3.weight(.semibold))

            TextEditor(text: $bodyText)
                .font(.body)
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Comment") {
                    onSubmit(bodyText)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560)
    }
}
