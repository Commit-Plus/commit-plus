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
    @AppStorage("commit.allChanges") private var commitAllChanges = false
    @ObservedObject var aiProviderController: AIProviderController
    @Binding var message: String
    @State private var messageSelection: TextSelection?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isAIGenerationRequested = false
    let repositoryURL: URL
    let hasStagedChanges: Bool
    let onCommit: (String, Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Commit Changes")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit Message")
                    .font(.headline)
                Text("Leave this empty to create a commit without a message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topTrailing) {
                    TextField(
                        "Enter a commit message…",
                        text: $message,
                        selection: $messageSelection,
                        axis: .vertical
                    )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 400)
                        .lineLimit(3...6)
                        .disabled(aiProviderController.isGenerating)
                        .onKeyPress(.return, phases: .down) { keyPress in
                            guard keyPress.modifiers == .shift else { return .ignored }
                            insertNewlineInMessage()
                            return .handled
                        }

                    generateCommitMessageButton
                        .padding(8)
                        .zIndex(1)
                }
                if !hasStagedChanges {
                    HStack(spacing: 8) {
                        Label("No files staged", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Toggle("Commit all changes", isOn: $commitAllChanges)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }
                    .frame(width: 400, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Commit Without Message" : "Commit") {
                    onCommit(message, !hasStagedChanges && commitAllChanges)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasStagedChanges && !commitAllChanges)
            }
        }
        .padding(30)
        .frame(minWidth: 480)
        .task {
            await aiProviderController.refreshAvailability()
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
            Task {
                await generateCommitMessage()
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
        .disabled(aiProviderController.isGenerating)
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

    private func insertNewlineInMessage() {
        guard let messageSelection,
              case let .selection(range) = messageSelection.indices else {
            message.append("\n")
            self.messageSelection = TextSelection(insertionPoint: message.endIndex)
            return
        }

        let insertionOffset = message.distance(from: message.startIndex, to: range.lowerBound)
        message.replaceSubrange(range, with: "\n")
        let insertionPoint = message.index(message.startIndex, offsetBy: insertionOffset + 1)
        self.messageSelection = TextSelection(insertionPoint: insertionPoint)
    }

    private func generateCommitMessage() async {
        do {
            async let branchName = GitStatusService.shared.currentBranch(in: repositoryURL)
            async let recentCommits = GitStatusService.shared.recentCommits(in: repositoryURL)
            let generated = try await aiProviderController.generateCommitMessage(
                repositoryURL: repositoryURL,
                branchName: await branchName,
                changeSource: hasStagedChanges ? .staged : .workingTree,
                recentCommitSubjects: await recentCommits.map(\.message)
            )
            message = generated.text
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
