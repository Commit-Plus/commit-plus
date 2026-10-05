//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
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

enum TagCommitSource: Hashable {
    case workingCopyParent
    case specified(String)
}

struct TagCreationRequest: Equatable {
    let name: String
    let source: TagCommitSource
    let pushRemote: String?

    var commitReference: String {
        switch source {
        case .workingCopyParent:
            return "HEAD"
        case .specified(let commit):
            return commit
        }
    }
}

enum TagCreationPolicy {
    static func canSubmit(name: String, source: TagCommitSource) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if case .specified(let commit) = source {
            return !commit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
}

struct TagSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let onRunRepositoryOperation: RepositoryOperationRunner
    let onCreate: (TagCreationRequest) async throws -> Void

    @State private var tagName = ""
    @State private var source: TagCommitSource = .workingCopyParent
    @State private var commitOptions: [BranchCommitInfo] = []
    @State private var selectedCommit = ""
    @State private var commitIDInput = ""
    @State private var resolvedCommit: BranchCommitInfo?
    @State private var hasResolvedCommitID = false
    @State private var commitIDError: String?
    @State private var isResolvingCommitID = false
    @State private var commitValidationTask: Task<Void, Never>?
    @State private var pushTag = false
    @State private var remotes: [String] = []
    @State private var selectedRemote = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @FocusState private var isCommitIDFocused: Bool

    private var canSubmit: Bool {
        TagCreationPolicy.canSubmit(name: tagName, source: source) && hasValidSelectedCommit
    }

    private var hasValidSelectedCommit: Bool {
        guard case .specified(let commit) = source else { return true }
        return commitIDError == nil &&
            !commitIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            commitIDInput.trimmingCharacters(in: .whitespacesAndNewlines) == commit
    }

    private var visibleCommitOptions: [BranchCommitInfo] {
        if hasResolvedCommitID, let resolvedCommit {
            return [resolvedCommit] + commitOptions.filter { $0.hash != resolvedCommit.hash }
        }
        return commitOptions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Tag")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tag Name:")
                    .font(.system(size: 13))
                TextField("Enter tag name...", text: $tagName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit:")
                    .font(.system(size: 13))

                Picker("", selection: $source) {
                    Text("Working copy parent").tag(TagCommitSource.workingCopyParent)
                    Text("Specified commit:").tag(TagCommitSource.specified(selectedCommit))
                }
                .pickerStyle(.radioGroup)

                if case .specified = source {
                    HStack(alignment: .top, spacing: 8) {
                        TextField("Commit ID", text: $commitIDInput)
                            .textFieldStyle(.roundedBorder)
                            .focused($isCommitIDFocused)
                            .onChange(of: commitIDInput) { _, _ in
                                commitValidationTask?.cancel()
                                resolvedCommit = nil
                                hasResolvedCommitID = false
                                commitIDError = nil
                                commitValidationTask = Task {
                                    try? await Task.sleep(for: .milliseconds(250))
                                    guard !Task.isCancelled else { return }
                                    await resolveCommitID()
                                }
                            }
                            .onChange(of: isCommitIDFocused) { _, isFocused in
                                guard !isFocused else { return }
                                commitValidationTask?.cancel()
                                commitValidationTask = Task {
                                    await resolveCommitID()
                                }
                            }
                            .onSubmit {
                                commitValidationTask?.cancel()
                                commitValidationTask = Task {
                                    await resolveCommitID()
                                }
                            }

                        SearchableReferencePicker(
                            title: "Tag commit", selection: selectedCommit,
                            options: visibleCommitOptions.map(\.hash),
                            searchPrompt: "Search commit SHA or message",
                            placeholder: "Select a commit…",
                            emptyMessage: "No matching commits",
                            referenceLabel: { hash in
                                guard let commit = visibleCommitOptions.first(where: { $0.hash == hash }) else { return hash }
                                return "\(hash.prefix(8)) \(commit.message)"
                            },
                            onSelect: { hash in
                                guard let commit = visibleCommitOptions.first(where: { $0.hash == hash }) else { return }
                                commitValidationTask?.cancel()
                                selectedCommit = hash
                                source = .specified(hash)
                                commitIDInput = hash
                                resolvedCommit = commit
                                hasResolvedCommitID = false
                                commitIDError = nil
                            })
                        .frame(minWidth: 240, maxWidth: .infinity)

                    }
                    if isResolvingCommitID {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 20)
                    } else if let commitIDError {
                        Text(commitIDError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .padding(.leading, 20)
                    } else if resolvedCommit != nil {
                        Text("Commit found")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }
                }
            }

            HStack(spacing: 8) {
                Toggle("Push tag:", isOn: $pushTag)
                    .toggleStyle(.checkbox)
                    .onChange(of: pushTag) { _, isEnabled in
                        if isEnabled, selectedRemote.isEmpty {
                            selectedRemote = remotes.first ?? ""
                        }
                    }

                if pushTag {
                    Picker("", selection: $selectedRemote) {
                        if remotes.isEmpty {
                            Text("No remotes configured").tag("")
                        } else {
                            ForEach(remotes, id: \.self) { remote in
                                Text(remote).tag(remote)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(remotes.isEmpty)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Tag") {
                    createTag()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || (pushTag && selectedRemote.isEmpty))
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
        .task {
            await loadData()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadData() async {
        async let commits = GitStatusService.shared.recentCommits(limit: 50, in: repositoryURL)
        async let loadedRemotes = GitStatusService.shared.remotes(in: repositoryURL)
        let (recent, remoteNames) = await (commits, loadedRemotes)

        await MainActor.run {
            commitOptions = recent.map { BranchCommitInfo(hash: $0.hash, message: $0.message) }
            selectedCommit = commitOptions.first?.hash ?? ""
            commitIDInput = selectedCommit
            resolvedCommit = commitOptions.first
            remotes = remoteNames
            selectedRemote = remoteNames.first ?? ""
        }
    }

    private func resolveCommitID() async {
        let input = commitIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            isResolvingCommitID = true
            resolvedCommit = nil
            hasResolvedCommitID = false
            commitIDError = nil
        }

        let resolved = await GitStatusService.shared.commitInfoIncludingRemotes(for: input, in: repositoryURL)
        await MainActor.run {
            guard commitIDInput.trimmingCharacters(in: .whitespacesAndNewlines) == input else {
                return
            }
            isResolvingCommitID = false
            guard let resolved else {
                selectedCommit = ""
                source = .specified("")
                commitIDError = input.isEmpty ? "Enter a commit ID." : "Commit not found."
                return
            }

            let commit = BranchCommitInfo(hash: resolved.hash, message: resolved.message)
            resolvedCommit = commit
            hasResolvedCommitID = true
            selectedCommit = commit.hash
            source = .specified(commit.hash)
        }
    }

    private func createTag() {
        let request = TagCreationRequest(
            name: tagName.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            pushRemote: pushTag ? selectedRemote : nil
        )

        onRunRepositoryOperation("Creating tag \(request.name)...") {
            do {
                try await onCreate(request)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}
