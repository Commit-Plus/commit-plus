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

struct FinishGitFlowSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialPlan: GitFlowFinishPlan
    let onRunRepositoryOperation: RepositoryOperationRunner
    let onValidateTag: @MainActor (String) async -> String?
    let onFinish: @MainActor (GitFlowFinishPlan) async -> Bool

    @State private var isFinishing = false
    @State private var strategy: GitFlowTopicFinishStrategy
    @State private var createTag: Bool
    @State private var tagName: String
    @State private var tagValidationMessage: String?
    @State private var isValidatingTag = false
    @State private var removeWorktree: Bool
    @State private var deleteSourceBranch: Bool
    @FocusState private var isTagNameFocused: Bool

    init(
        plan: GitFlowFinishPlan,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner,
        onValidateTag: @escaping @MainActor (String) async -> String?,
        onFinish: @escaping @MainActor (GitFlowFinishPlan) async -> Bool
    ) {
        initialPlan = plan
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.onValidateTag = onValidateTag
        self.onFinish = onFinish
        _removeWorktree = State(initialValue: plan.removeWorktree)
        _strategy = State(initialValue: plan.strategy)
        _createTag = State(initialValue: plan.createTag)
        _tagName = State(initialValue: plan.tagName ?? "")
        _deleteSourceBranch = State(initialValue: plan.deleteSourceBranch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Finish \(initialPlan.kind.displayName)")
                .font(.title2)
                .bold()

            LabeledContent("Source") { Text(initialPlan.sourceBranch).bold() }
            targetSummary
            finishControls
            executionPreview

            Toggle("Delete local branch", isOn: $deleteSourceBranch)
                .toggleStyle(.switch)
                .accessibilityHint("Deletes only the local topic branch after every finish step succeeds.")

            if let path = initialPlan.worktreePath {
                Toggle("Remove local worktree", isOn: $removeWorktree)
                    .toggleStyle(.switch)
                Text(path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Only clean, unlocked worktrees are removed after Finish succeeds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isFinishing)
                if isFinishing { ProgressView().controlSize(.small) }
                Button("Finish \(initialPlan.kind.displayName)", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                    .disabled(isFinishDisabled)
            }
        }
        .padding(24)
        .frame(minWidth: 500, idealWidth: 540)
        .interactiveDismissDisabled(isFinishing)
        .task(id: tagValidationKey) {
            await validateTagIfNeeded()
        }
        .onAppear {
            isTagNameFocused = initialPlan.kind.requiresReleaseTag && createTag
        }
        .onChange(of: createTag) { _, isEnabled in
            if isEnabled { isTagNameFocused = true }
        }
    }

    @ViewBuilder
    private var targetSummary: some View {
        if initialPlan.kind.requiresReleaseTag {
            LabeledContent("Merge order") {
                Text(initialPlan.targetBranches.joined(separator: " → ")).bold()
            }
            LabeledContent("Strategy") { Text("Merge with --no-ff") }
        } else {
            LabeledContent("Finish into") { Text(initialPlan.targetBranch).bold() }
        }
    }

    @ViewBuilder
    private var finishControls: some View {
        if initialPlan.kind.requiresReleaseTag {
            Toggle("Create annotated tag", isOn: $createTag)
                .toggleStyle(.checkbox)
                .accessibilityHint("Creates the tag on the Main merge commit. No remote tag is pushed.")
            if createTag {
                LabeledContent("Tag name") {
                    TextField("Version tag", text: $tagName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                        .focused($isTagNameFocused)
                        .accessibilityLabel("Annotated tag name")
                }
                if isValidatingTag {
                    Label("Checking tag…", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let tagValidationMessage {
                    Label(tagValidationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Tag validation error: \(tagValidationMessage)")
                }
            }
        } else {
            Picker("Strategy", selection: $strategy) {
                ForEach(GitFlowTopicFinishStrategy.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Finish strategy")
            .accessibilityValue(strategy.displayName)
            .accessibilityHint("Choose a merge commit or rebase followed by fast-forward.")
        }
    }

    private var executionPreview: some View {
        Label(previewText, systemImage: strategyIcon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Finish preview: \(previewText)")
    }

    private var previewText: String {
        if initialPlan.kind.requiresReleaseTag {
            let normalizedTag = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            let tagCopy = createTag
                ? " The annotated tag '\(normalizedTag)' will be created on the Main merge."
                : " No tag will be created."
            let deletionCopy = deleteSourceBranch
                ? " The local source branch will be deleted after both merges succeed."
                : " The local source branch will be kept."
            return "Commit+ will merge into \(initialPlan.targetBranches.joined(separator: ", then ")).\(tagCopy)\(deletionCopy)"
        }
        if strategy == .rebaseFastForward {
            return "Commit+ will rebase \(initialPlan.sourceBranch) onto \(initialPlan.targetBranch), then fast-forward \(initialPlan.targetBranch). This rewrites the local topic branch and will not force-push it."
        }
        return "Commit+ will check out \(initialPlan.targetBranch) and create a merge commit."
    }

    private var strategyIcon: String {
        strategy == .rebaseFastForward && !initialPlan.kind.requiresReleaseTag
            ? "arrow.triangle.2.circlepath"
            : "arrow.triangle.merge"
    }

    private var tagValidationKey: String {
        "\(createTag):\(tagName)"
    }

    private var isFinishDisabled: Bool {
        isFinishing || (initialPlan.kind.requiresReleaseTag
            && createTag
            && (isValidatingTag || tagValidationMessage != nil))
    }

    private func validateTagIfNeeded() async {
        guard initialPlan.kind.requiresReleaseTag, createTag else {
            tagValidationMessage = nil
            isValidatingTag = false
            return
        }
        isValidatingTag = true
        let message = await onValidateTag(tagName)
        guard !Task.isCancelled else { return }
        tagValidationMessage = message
        isValidatingTag = false
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        let shouldCreateTag = initialPlan.kind.requiresReleaseTag && createTag
        let plan = GitFlowFinishPlan(
            kind: initialPlan.kind,
            sourceBranch: initialPlan.sourceBranch,
            targetBranch: initialPlan.primaryTargetBranch,
            secondaryTargetBranch: initialPlan.secondaryTargetBranch,
            tagName: shouldCreateTag ? tagName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            createTag: shouldCreateTag,
            deleteSourceBranch: deleteSourceBranch,
            worktreePath: initialPlan.worktreePath,
            removeWorktree: removeWorktree,
            strategy: initialPlan.kind.requiresReleaseTag ? .mergeNoFastForward : strategy
        )
        onRunRepositoryOperation("Finishing \(plan.sourceBranch)…") {
            let succeeded = await onFinish(plan)
            await MainActor.run {
                isFinishing = false
                if succeeded { dismiss() }
            }
        }
    }
}
