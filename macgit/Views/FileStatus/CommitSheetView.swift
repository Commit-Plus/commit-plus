//
//  CommitSheetView.swift
//  macgit
//

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

struct CommitSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTextScale) private var textScale
    @AppStorage("commit.allChanges") private var commitAllChanges = false
    @ObservedObject var aiProviderController: AIProviderController
    @Binding var message: String
    @State private var subject: String
    @State private var descriptionText: String
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isAIGenerationRequested = false
    @State private var aiGenerationTask: Task<Void, Never>?
    let repositoryURL: URL
    let hasStagedChanges: Bool
    let onCommit: @MainActor (String, Bool) async throws -> Bool
    @State private var isCommitting = false
    @State private var commitErrorMessage: String?

    init(
        aiProviderController: AIProviderController,
        message: Binding<String>,
        repositoryURL: URL,
        hasStagedChanges: Bool,
        onCommit: @escaping @MainActor (String, Bool) async throws -> Bool
    ) {
        self.aiProviderController = aiProviderController
        _message = message
        let draft = CommitMessageDraft(message: message.wrappedValue)
        _subject = State(initialValue: draft.subject)
        _descriptionText = State(initialValue: draft.body)
        self.repositoryURL = repositoryURL
        self.hasStagedChanges = hasStagedChanges
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Commit Changes")
                .font(.title2.scaled(by: textScale))
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Commit Message")
                        .font(.headline.scaled(by: textScale))
                    Spacer()
                    generateCommitMessageButton
                }
                .frame(width: 440)
                Text("Add a short title and an optional description. Leave both empty to commit without a message.")
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $subject)
                        .accessibilityLabel("Commit title")

                    TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Commit description")
                        .onKeyPress(.return, phases: .down) { keyPress in
                            guard keyPress.modifiers == .shift else { return .ignored }
                            insertNewlineInMessage()
                            return .handled
                        }
                }
                .font(.body.scaled(by: textScale))
                .textFieldStyle(.roundedBorder)
                .frame(width: 440)
                .disabled(aiProviderController.isGenerating || isCommitting)
                if !hasStagedChanges {
                    HStack(spacing: 8) {
                        Label("No files staged", systemImage: "exclamationmark.triangle")
                            .font(.caption.scaled(by: textScale))
                            .foregroundStyle(.orange)
                        Spacer()
                        Toggle("Commit all changes", isOn: $commitAllChanges)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12).scaled(by: textScale))
                    }
                    .frame(width: 440, alignment: .leading)
                }
            }

            if let commitErrorMessage {
                Label(commitErrorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled).frame(width: 440, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    cancelCommitMessageGeneration()
                    dismiss()
                }
                .font(.body.scaled(by: textScale))
                .keyboardShortcut(.cancelAction)
                .disabled(isCommitting)
                if isCommitting { ProgressView().controlSize(.small) }

                Button(commitMessage.isEmpty ? "Commit Without Message" : "Commit") {
                    guard !isCommitting else { return }
                    let requestedMessage = commitMessage
                    let requestedAllChanges = !hasStagedChanges && commitAllChanges
                    isCommitting = true
                    commitErrorMessage = nil
                    Task {
                        defer { isCommitting = false }
                        do {
                            if try await onCommit(requestedMessage, requestedAllChanges) { dismiss() }
                        } catch { commitErrorMessage = error.localizedDescription }
                    }
                }
                .font(.body.scaled(by: textScale))
                .keyboardShortcut(.defaultAction)
                .disabled(isCommitting || (!hasStagedChanges && !commitAllChanges))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(minWidth: 480)
        .onChange(of: subject) { _, _ in updateMessageBinding() }
        .onChange(of: descriptionText) { _, _ in updateMessageBinding() }
        .interactiveDismissDisabled(isCommitting)
        .onDisappear { cancelCommitMessageGeneration() }
        .task {
            await aiProviderController.refreshAvailability(selectedOnly: true)
        }
        .alert("Unable to Generate Commit Message", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .aiCommitMessageAccessGate(
            isRequested: $isAIGenerationRequested,
            requiresProAccess: aiProviderController.selectedDescriptor.billing.requiresProAccess
        ) {
            aiGenerationTask = Task {
                await generateCommitMessage()
                if !Task.isCancelled { aiGenerationTask = nil }
            }
        }
    }

    private var generateCommitMessageButton: some View {
        Button {
            isAIGenerationRequested = true
        } label: {
            ZStack {
                Label("Generate commit message", systemImage: "sparkles")
                    .labelStyle(.iconOnly)
                    .opacity(aiProviderController.isGenerating ? 0 : 1)

                if aiProviderController.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
        .disabled(aiProviderController.isGenerating || isCommitting)
        .help(generateCommitMessageHelp)
        .accessibilityLabel(aiProviderController.isGenerating
            ? "Generating commit message"
            : "Generate commit message")
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }

    private var generateCommitMessageHelp: String {
        if !aiProviderController.selectedProviderAvailability.isAvailable {
            return aiProviderController.selectedProviderAvailability.detail
        }
        return hasStagedChanges
            ? "Generate an editable message from staged changes."
            : "Generate an editable message from changed files."
    }

    private var commitMessage: String {
        CommitMessageDraft(subject: subject, body: descriptionText).message
    }

    private func updateMessageBinding() {
        message = commitMessage
    }

    private func insertNewlineInMessage() {
        // A field editor treats insertNewline as ending editing and selects the text again.
        NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
    }

    private func cancelCommitMessageGeneration() {
        guard let task = aiGenerationTask else { return }
        task.cancel()
        aiGenerationTask = nil
        aiProviderController.cancelCommitMessageGeneration()
    }

    private func generateCommitMessage() async {
        do {
            try Task.checkCancellation()
            async let branchName = GitStatusService.shared.currentBranch(in: repositoryURL)
            async let recentCommits = GitStatusService.shared.recentCommits(in: repositoryURL)
            let generated = try await aiProviderController.generateCommitMessage(
                repositoryURL: repositoryURL,
                branchName: await branchName,
                changeSource: hasStagedChanges ? .staged : .workingTree,
                recentCommitSubjects: await recentCommits.map(\.message)
            )
            try Task.checkCancellation()
            let draft = generated.normalized
            subject = draft.subject
            descriptionText = draft.body
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
