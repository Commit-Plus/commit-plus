// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct HistoryTagSheet: View {
    let commit: Commit
    let controller: HistoryCommitActionController
    @State private var tagNameInput = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Tag")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tag name:")
                    .font(.system(size: 13))
                TextField("Enter tag name...", text: $tagNameInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    controller.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Tag") {
                    controller.createTag(commit, name: tagNameInput)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320, idealWidth: 360)
    }
}

struct HistoryBranchSheet: View {
    let commit: Commit
    let controller: HistoryCommitActionController
    @State private var branchNameInput = ""
    @State private var checkoutNewBranch = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Branch")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("From commit:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(commit.shortHash) : \(commit.message)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Branch name:")
                    .font(.system(size: 13))
                TextField("Enter branch name...", text: $branchNameInput)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Checkout new branch", isOn: $checkoutNewBranch)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    controller.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Branch") {
                    controller.createBranch(commit, name: branchNameInput, checkout: checkoutNewBranch)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
}

struct HistoryResetSheet: View {
    let commit: Commit
    let controller: HistoryCommitActionController
    let branchName: String
    @State private var resetMode: ResetMode = .mixed

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset to this commit?")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("This will reset '")
                        .font(.system(size: 13))
                    Text(branchName.isEmpty ? "current branch" : branchName)
                        .font(.system(size: 13, weight: .bold))
                    Text("' to:")
                        .font(.system(size: 13))
                }
                Text("\(commit.shortHash) : \(commit.message)")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reset mode:")
                    .font(.system(size: 13))

                Picker("", selection: $resetMode) {
                    Text("Soft – keep all local changes").tag(ResetMode.soft)
                    Text("Mixed – keep working copy but reset index").tag(ResetMode.mixed)
                    Text("Hard – discard all working copy changes").tag(ResetMode.hard)
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 12))
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    controller.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Reset", role: .destructive) {
                    controller.reset(commit, mode: resetMode)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
}

struct HistoryMergeSheet: View {
    let commit: Commit
    let controller: HistoryCommitActionController
    @State private var mergeCommitImmediately = true
    @State private var mergeIncludeMessages = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Merge")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Are you sure you want to merge into your current branch?")
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Commit merged changes immediately", isOn: $mergeCommitImmediately)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Toggle("Include messages from commits being merged in merge commit", isOn: $mergeIncludeMessages)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    controller.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    controller.merge(commit, commitImmediately: mergeCommitImmediately, includeMessages: mergeIncludeMessages)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 460)
    }
}

struct HistoryRebaseSheet: View {
    let commit: Commit
    let controller: HistoryCommitActionController


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Rebase")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Are you sure you want to rebase your current changes on to '\(commit.shortHash)'?")
                .font(.system(size: 13))

            Text("Make sure your changes have not been pushed to anyone else.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    controller.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    controller.rebase(commit)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
}

struct HistoryCheckoutSheet: View {
    let commit: Commit
    let controller: HistoryCommitActionController
    let hasUncommittedChanges: Bool
    @State private var discardLocalChanges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm change working copy")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Are you sure you want to checkout '\(commit.shortHash)'?")
                .font(.system(size: 13))

            Text("Doing so will make your working copy a 'detached HEAD', which means you won't be on a branch anymore. If you want to commit after this you'll probably want to either checkout a branch again, or create a new branch. Is this ok?")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if hasUncommittedChanges {
                Toggle("Discard local changes", isOn: $discardLocalChanges)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    controller.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    controller.checkout(commit, discard: discardLocalChanges)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
}

private struct HistoryActionPresentationsModifier: ViewModifier {
    @Bindable var controller: HistoryCommitActionController

    private var showingRevert: Binding<Bool> {
        Binding(get: { controller.revertCandidate != nil }, set: { if !$0 { controller.revertCandidate = nil } })
    }
    private var showingError: Binding<Bool> {
        Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })
    }

    func body(content: Content) -> some View {
        content
            .replacingSheet(item: $controller.presentation) { presentation in
                switch presentation {
                case .tag(let commit):
                    HistoryTagSheet(commit: commit, controller: controller)
                case .branch(let commit):
                    HistoryBranchSheet(commit: commit, controller: controller)
                case .reset(let commit, let branchName):
                    HistoryResetSheet(commit: commit, controller: controller, branchName: branchName)
                case .merge(let commit):
                    HistoryMergeSheet(commit: commit, controller: controller)
                case .rebase(let commit):
                    HistoryRebaseSheet(commit: commit, controller: controller)
                case .checkout(let commit, let hasChanges):
                    HistoryCheckoutSheet(commit: commit, controller: controller, hasUncommittedChanges: hasChanges)
                case .squash(let commits, let message):
                    SquashCommitsSheet(commits: commits, initialMessage: message,
                        onCancel: controller.dismiss,
                        onConfirm: { controller.squash(commits, message: $0) })
                }
            }
            .alert("Reverse this commit?", isPresented: showingRevert, presenting: controller.revertCandidate) { commit in
                Button("Cancel", role: .cancel) { controller.dismiss() }
                Button("Revert") { controller.revert(commit) }
            } message: { commit in
                Text("This will create a new commit that undoes the changes in \(commit.shortHash).")
            }
            .alert("Error", isPresented: showingError) {
                Button("OK", role: .cancel) { controller.errorMessage = nil }
            } message: {
                Text(controller.errorMessage ?? "")
            }
    }
}

extension View {
    func historyActionPresentations(_ controller: HistoryCommitActionController) -> some View {
        modifier(HistoryActionPresentationsModifier(controller: controller))
    }
}
