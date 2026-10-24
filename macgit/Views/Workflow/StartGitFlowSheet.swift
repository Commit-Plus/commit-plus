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

struct StartGitFlowSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: GitFlowTopicKind
    let configuration: GitFlowConfiguration
    let worktreeRootURL: URL
    let onRunRepositoryOperation: RepositoryOperationRunner
    let onStart: @MainActor (GitFlowStartPlan, Bool) async throws -> Bool

    @State private var topicName = ""
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var destination: GitFlowStartDestination
    @State private var worktreePath = ""
    @State private var worktreeLabel = ""
    @State private var openAfterCreate = true
    @State private var hasEditedWorktreePath = false
    @FocusState private var isTopicNameFocused: Bool

    init(
        kind: GitFlowTopicKind,
        configuration: GitFlowConfiguration,
        worktreeRootURL: URL,
        initialTopicName: String? = nil,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner,
        onStart: @escaping @MainActor (GitFlowStartPlan, Bool) async throws -> Bool
    ) {
        self.kind = kind
        _topicName = State(initialValue: initialTopicName ?? "")
        self.configuration = configuration
        self.worktreeRootURL = worktreeRootURL
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.onStart = onStart
        _destination = State(initialValue: configuration.defaultStartDestination)
    }

    private var plan: GitFlowStartPlan? {
        let path: URL?
        if destination == .newWorktree {
            path = WorktreePathPolicy.normalizedURL(fromAbsolutePath: worktreePath)
            guard path != nil, worktreePathError == nil else { return nil }
        } else {
            path = nil
        }
        return try? GitFlowPlanner().startPlan(
            kind: kind,
            topicName: sanitizedTopicName,
            configuration: configuration,
            destination: destination,
            worktreePath: path,
            worktreeLabel: worktreeLabel
        )
    }

    private var sanitizedTopicName: String {
        GitBranchNameSanitizer.sanitize(topicName)
    }

    private var resolvedBranchName: String {
        configuration.normalized().prefix(for: kind)
            + sanitizedTopicName
    }

    private var suggestedWorktreePath: String {
        WorktreePathPolicy.suggestedPath(
            root: worktreeRootURL,
            branchName: resolvedBranchName
        ).path
    }

    private var worktreePathError: String? {
        guard destination == .newWorktree else { return nil }
        guard let path = WorktreePathPolicy.normalizedURL(fromAbsolutePath: worktreePath) else {
            return "Enter an absolute worktree path."
        }
        if FileManager.default.fileExists(atPath: path.path) {
            return "A file or folder already exists at this path."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start \(kind.displayName)")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)

                HStack(spacing: 0) {
                    Text(configuration.normalized().prefix(for: kind))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)

                    TextField("branch-name", text: $topicName)
                        .focused($isTopicNameFocused)
                        .accessibilityLabel("\(kind.displayName) branch name")
                        .accessibilityHint("The configured prefix is added automatically.")
                        .textFieldStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.trailing, 8)
                }
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }

                Text("Starting point: \(configuration.baseBranch(for: kind))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Start new flow:")
                    .font(.subheadline)

                Picker("", selection: $destination) {
                    Text("Current working copy")
                        .tag(GitFlowStartDestination.currentWorkingCopy)
                    Text("Worktree")
                        .tag(GitFlowStartDestination.newWorktree)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .padding(.leading, 2)
                .accessibilityLabel("Start destination")
                .accessibilityValue(destination.displayName)
                .accessibilityHint("Choose the current working copy or a new linked worktree.")
            }
            .onChange(of: destination) { _, newDestination in
                if newDestination == .newWorktree, worktreePath.isEmpty {
                    worktreePath = suggestedWorktreePath
                }
            }

            if destination == .newWorktree {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Worktree path")
                            .font(.subheadline)
                        TextField("/absolute/path/to/worktree", text: $worktreePath) { isEditing in
                            if isEditing {
                                hasEditedWorktreePath = true
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Worktree path")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Label (optional)")
                            .font(.subheadline)
                        TextField("Task label", text: $worktreeLabel)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Worktree label")
                    }

                    Toggle("Open after create", isOn: $openAfterCreate)
                        .toggleStyle(.checkbox)
                        .accessibilityHint("Opens the new linked worktree in a Commit+ window after creation.")

                    if let worktreePathError {
                        Label(worktreePathError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Worktree path error: \(worktreePathError)")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let plan {
                Label(previewText(for: plan), systemImage: "arrow.triangle.branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityLabel("Start failed: \(errorMessage)")
            }

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isStarting)
                if isStarting { ProgressView().controlSize(.small) }

                Button(isStarting ? "Starting…" : "Start \(kind.displayName)") {
                    guard let plan, !isStarting else { return }
                    isStarting = true
                    errorMessage = nil
                    onRunRepositoryOperation("Starting \(plan.branchName)...") {
                        do {
                            let succeeded = try await onStart(plan, destination == .newWorktree && openAfterCreate)
                            await MainActor.run {
                                isStarting = false
                                if succeeded { dismiss() }
                            }
                        } catch {
                            await MainActor.run {
                                isStarting = false
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(isStarting || plan == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 520)
        .interactiveDismissDisabled(isStarting)
        .onAppear {
            isTopicNameFocused = true
            if destination == .newWorktree, worktreePath.isEmpty {
                worktreePath = suggestedWorktreePath
            }
        }
        .onChange(of: topicName) { _, _ in
            if destination == .newWorktree, !hasEditedWorktreePath {
                worktreePath = suggestedWorktreePath
            }
        }
    }

    private func previewText(for plan: GitFlowStartPlan) -> String {
        switch plan.destination {
        case .currentWorkingCopy:
            return "Creates and checks out \(plan.branchName) from \(plan.baseBranch)."
        case .newWorktree:
            return "Creates \(plan.branchName) from \(plan.baseBranch) in a new worktree. The current working copy stays unchanged."
        }
    }
}
