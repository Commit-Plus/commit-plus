//
//  BranchSheetView.swift
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

enum BranchTab: String, CaseIterable {
    case create = "New Branch"
    case delete = "Delete Branches"
}

struct BranchCommitInfo: Identifiable, Hashable {
    let id = UUID()
    let hash: String
    let message: String

    var display: String {
        "\(hash) \(message)"
    }
}

struct BranchDeleteItem: Identifiable {
    let id = UUID()
    let name: String
    let type: BranchType
    let remoteTarget: RemoteBranchDeleteTarget?
    var isSelected: Bool = false

    init(
        name: String,
        type: BranchType,
        remoteTarget: RemoteBranchDeleteTarget? = nil,
        isSelected: Bool = false
    ) {
        self.name = name
        self.type = type
        self.remoteTarget = remoteTarget
        self.isSelected = isSelected
    }
}

enum BranchType: String {
    case local = "Local"
    case remote = "Remote"
}

struct BranchSheetView: View {
    struct InitialCreateState: Equatable {
        let useWorkingCopyParent: Bool
        let selectedStartPoint: GitBranchStartPoint?
        let selectedStartReference: String
    }

    @Environment(\.dismiss) private var dismiss
    let repositoryURL: URL
    let onCompleted: () -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner
    var undoManager: GitUndoManager? = nil
    var initialStartPoint: GitBranchStartPoint? = nil
    let initiallySelectedLocalBranches: Set<String>
    let localBranchFilter: Set<String>?
    let validateLocalBranchDeletion: (@MainActor (String) async throws -> String)?
    let onRunBackgroundRemoteBranchDeletion: RemoteBranchDeletionRunner
    let onCommitAllChangesRequested: (() -> Void)?

    @State private var selectedTab: BranchTab = .create

    // Create tab state
    @State private var currentBranch: String = ""
    @State private var branchNameInput: String = ""
    @State private var sanitizedName: String = ""
    @State private var useWorkingCopyParent = true
    @State private var selectedStartPoint: GitBranchStartPoint? = nil
    @State private var selectedStartReference: String = ""
    @State private var startPointCommitIDInput: String = ""
    @State private var resolvedStartPointCommit: BranchCommitInfo?
    @State private var hasResolvedStartPointCommitID = false
    @State private var startPointCommitIDError: String?
    @State private var isResolvingStartPointCommit = false
    @State private var startPointCommitValidationTask: Task<Void, Never>?
    @State private var recentCommits: [BranchCommitInfo] = []
    @State private var checkoutNewBranch = true
    @State private var commitAllChanges = false
    @State private var hasAppliedInitialCreateState = false

    // Delete tab state
    @State private var branches: [BranchDeleteItem] = []
    @State private var forceDelete = false
    @State private var deleteMatchingRemoteBranches = false
    @State private var hasAppliedInitialDeleteSelection = false

    // Confirmation overlay
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @FocusState private var isStartPointCommitIDFocused: Bool

    // Alerts
    @State private var errorMessage: String = ""
    @State private var showingError = false

    init(
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        initialStartPoint: GitBranchStartPoint? = nil,
        initialTab: BranchTab = .create,
        initiallySelectedLocalBranches: Set<String> = [],
        initialForceDelete: Bool = false,
        localBranchFilter: Set<String>? = nil,
        validateLocalBranchDeletion: (@MainActor (String) async throws -> String)? = nil,
        onRunBackgroundRemoteBranchDeletion: @escaping RemoteBranchDeletionRunner,
        onCommitAllChangesRequested: (() -> Void)? = nil,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner = { _, operation in
            Task { await operation() }
        },
        onCompleted: @escaping () -> Void
    ) {
        self.repositoryURL = repositoryURL
        self.onCompleted = onCompleted
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.undoManager = undoManager
        self.initialStartPoint = initialStartPoint
        self.initiallySelectedLocalBranches = initiallySelectedLocalBranches
        self.localBranchFilter = localBranchFilter
        self.validateLocalBranchDeletion = validateLocalBranchDeletion
        self.onRunBackgroundRemoteBranchDeletion = onRunBackgroundRemoteBranchDeletion
        self.onCommitAllChangesRequested = onCommitAllChangesRequested
        self._selectedTab = State(initialValue: initialTab)
        self._forceDelete = State(initialValue: initialForceDelete)
    }

    private var canCreate: Bool {
        !sanitizedName.isEmpty &&
        (useWorkingCopyParent || isBranchStartPoint || (hasValidSelectedCommitInput && startPointCommitIDError == nil))
    }

    private var isBranchStartPoint: Bool {
        if case .branch = selectedStartPoint { return true }
        return false
    }

    private var hasValidSelectedCommitInput: Bool {
        guard case .commit(let hash, _) = selectedStartPoint else { return false }
        return !startPointCommitIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            startPointCommitIDInput.trimmingCharacters(in: .whitespacesAndNewlines) == hash
    }

    private var selectedBranches: [BranchDeleteItem] {
        branches.filter { $0.isSelected }
    }

    private var canDelete: Bool {
        !selectedBranches.isEmpty
    }

    private var matchingRemoteTargets: [RemoteBranchDeleteTarget] {
        Self.matchingRemoteTargets(for: selectedBranches)
    }

    static func matchingRemoteTargets(for branches: [BranchDeleteItem]) -> [RemoteBranchDeleteTarget] {
        Array(Set(branches.compactMap { item in
            item.type == .local ? item.remoteTarget : nil
        })).sorted { $0.fullPath < $1.fullPath }
    }

    private var commitPickerOptions: [BranchCommitInfo] {
        Self.commitPickerOptions(
            selectedStartPoint: selectedStartPoint,
            recentCommits: recentCommits
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(selectedTab == .create ? "New Branch" : "Delete Branches")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(width: 160, alignment: .leading)
                    Spacer()
                    Picker("", selection: $selectedTab) {
                        ForEach(BranchTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding([.top, .horizontal], 24)

                Divider()
                    .padding(.top, 12)

                // Content
                if selectedTab == .create {
                    createBranchContent
                        .padding(24)
                } else {
                    deleteBranchesContent
                        .padding(24)
                }

                // Buttons
                HStack(spacing: 12) {
                    if selectedTab == .delete {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Force delete", isOn: $forceDelete)
                                .help("Delete branches regardless of merge status")

                            Toggle(
                                "Also delete matching remote branches",
                                isOn: $deleteMatchingRemoteBranches
                            )
                            .disabled(matchingRemoteTargets.isEmpty)
                            .help(
                                matchingRemoteTargets.isEmpty
                                    ? "No tracked or matching remote branches are available"
                                    : "Delete tracked or matching branches from their remotes"
                            )
                        }
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                    }

                    Spacer()
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    if selectedTab == .create {
                        Button("Create Branch") {
                            onRunRepositoryOperation("Creating branch \(sanitizedName)...") {
                                await createBranch()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                        .disabled(!canCreate)
                    } else {
                        Button("Delete Branches") {
                            showingDeleteConfirmation = true
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(GlassProminentButtonStyle(tint: .red, fontSize: 13))
                        .disabled(!canDelete)
                    }
                }
                .padding([.horizontal, .bottom], 24)
            }
            .frame(width: 640)
            .fixedSize(horizontal: false, vertical: true)

            // Custom confirmation overlay
            if showingDeleteConfirmation {
                deleteConfirmationOverlay
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadCreateData()
            await loadDeleteData()
        }
        .onChange(of: selectedTab) { _, _ in
            if selectedTab == .create {
                Task { await loadCreateData() }
            } else {
                Task { await loadDeleteData() }
            }
        }
        .onChange(of: matchingRemoteTargets.isEmpty) { _, isEmpty in
            if isEmpty {
                deleteMatchingRemoteBranches = false
            }
        }
    }

    // MARK: - Delete Confirmation Overlay

    private var deleteConfirmationOverlay: some View {
        Color.black.opacity(0.25)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 16) {
                    Text("Confirm Delete")
                        .font(.headline)

                    Text("Are you sure you want to delete the selected branches?")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)

                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(selectedBranches) { branch in
                                Text("• \(branch.name)")
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if deleteMatchingRemoteBranches {
                                ForEach(matchingRemoteTargets, id: \.self) { target in
                                    Text("• \(target.fullPath) (remote)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 240, alignment: .leading)

                    HStack(spacing: 12) {
                        Button("Cancel", role: .cancel) {
                            if !isDeleting {
                                showingDeleteConfirmation = false
                            }
                        }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isDeleting)

                        Button(isDeleting ? "Deleting..." : "Delete") {
                            onRunRepositoryOperation("Deleting branches...") {
                                await deleteSelectedBranches()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(GlassProminentButtonStyle(tint: .red, fontSize: 13))
                        .disabled(isDeleting)
                    }
                }
                .padding(24)
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 440)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
    }

    // MARK: - Create Branch Content

    private var createBranchContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current branch
            VStack(alignment: .leading, spacing: 4) {
                Text("Current branch")
                    .font(.system(size: 13))
                Text(currentBranch)
                    .font(.system(size: 13, weight: .medium))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // New branch name
            VStack(alignment: .leading, spacing: 4) {
                Text("New Branch:")
                    .font(.system(size: 13))
                TextField("Enter branch name...", text: $branchNameInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: branchNameInput) { _, newValue in
                        sanitizedName = GitBranchNameSanitizer.sanitize(newValue)
                    }
                if !sanitizedName.isEmpty {
                    Text(sanitizedName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Commit source
            VStack(alignment: .leading, spacing: 8) {
                Text("Commit:")
                    .font(.system(size: 13))

                Picker("", selection: $useWorkingCopyParent) {
                    Text("Working copy parent").tag(true)
                    Text("Specified start point:").tag(false)
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 12))
                .onChange(of: useWorkingCopyParent) { _, newValue in
                    guard !newValue else { return }
                    if selectedStartReference.isEmpty {
                        selectedStartReference = recentCommits.first?.hash ?? ""
                    }
                    if selectedStartPoint == nil,
                       let matchingCommit = recentCommits.first(where: { $0.hash == selectedStartReference }) {
                        selectedStartPoint = .commit(
                            hash: matchingCommit.hash,
                            message: matchingCommit.message
                        )
                    }
                    if let matchingCommit = recentCommits.first(where: { $0.hash == selectedStartReference }) {
                        startPointCommitIDInput = matchingCommit.hash
                        resolvedStartPointCommit = matchingCommit
                        hasResolvedStartPointCommitID = false
                        startPointCommitIDError = nil
                    }
                }

                if !useWorkingCopyParent {
                    if case .branch(let branchName) = selectedStartPoint {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Starting from branch:")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(branchName)
                                .font(.system(size: 13, weight: .medium))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .padding(.leading, 16)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            TextField("Commit ID", text: $startPointCommitIDInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 220, maxWidth: .infinity)
                                .layoutPriority(1)
                                .focused($isStartPointCommitIDFocused)
                                .onChange(of: startPointCommitIDInput) { _, _ in
                                    startPointCommitValidationTask?.cancel()
                                    resolvedStartPointCommit = nil
                                    hasResolvedStartPointCommitID = false
                                    startPointCommitIDError = nil
                                    startPointCommitValidationTask = Task {
                                        try? await Task.sleep(for: .milliseconds(250))
                                        guard !Task.isCancelled else { return }
                                        await resolveStartPointCommitID()
                                    }
                                }
                                .onChange(of: isStartPointCommitIDFocused) { _, isFocused in
                                    guard !isFocused else { return }
                                    startPointCommitValidationTask?.cancel()
                                    startPointCommitValidationTask = Task {
                                        await resolveStartPointCommitID()
                                    }
                                }
                                .onSubmit {
                                    startPointCommitValidationTask?.cancel()
                                    startPointCommitValidationTask = Task {
                                        await resolveStartPointCommitID()
                                    }
                                }

                            SearchableReferencePicker(
                                title: "Start commit", selection: selectedStartReference,
                                options: commitPickerOptions.map(\.hash),
                                searchPrompt: "Search commit SHA or message",
                                placeholder: "Select a commit…",
                                emptyMessage: "No matching commits",
                                referenceLabel: { hash in
                                    guard let commit = commitPickerOptions.first(where: { $0.hash == hash }) else { return hash }
                                    return "\(hash.prefix(8)) \(commit.message)"
                                },
                                onSelect: { hash in
                                    guard let commit = commitPickerOptions.first(where: { $0.hash == hash }) else { return }
                                    startPointCommitValidationTask?.cancel()
                                    selectedStartReference = hash
                                    selectedStartPoint = .commit(hash: hash, message: commit.message)
                                    startPointCommitIDInput = hash
                                    resolvedStartPointCommit = commit
                                    hasResolvedStartPointCommitID = false
                                    startPointCommitIDError = nil
                                })
                            .frame(minWidth: 180, maxWidth: .infinity)

                        }
                        .padding(.leading, 16)
                        if isResolvingStartPointCommit {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 16)
                        } else if let startPointCommitIDError {
                            Text(startPointCommitIDError)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .padding(.leading, 16)
                        } else if resolvedStartPointCommit != nil {
                            Text("Commit found")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 16)
                        }
                    }
                }
            }

            // Checkout
            Toggle("Checkout new branch", isOn: $checkoutNewBranch)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .onChange(of: checkoutNewBranch) { _, isOn in
                    if !isOn { commitAllChanges = false }
                }

            if onCommitAllChangesRequested != nil {
                Toggle("Commit all changes", isOn: $commitAllChanges)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .disabled(!checkoutNewBranch)
            }
        }
    }

    // MARK: - Delete Branches Content

    private var deleteBranchesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select the branches you wish to delete:")
                .font(.system(size: 13))

            ZStack(alignment: .topLeading) {
                Table($branches) {
                    TableColumn("") { $branch in
                        Toggle(branch.name, isOn: $branch.isSelected)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                    }
                    .width(44)

                    TableColumn("Branch name") { $branch in
                        Button {
                            branch.isSelected.toggle()
                        } label: {
                            Text(branch.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    }
                    .width(min: 220, ideal: 300)

                    TableColumn("Type") { $branch in
                        Text(branch.type.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    .width(70)

                    TableColumn("Remote branch") { $branch in
                        Text(branch.remoteTarget?.fullPath ?? "—")
                            .foregroundStyle(branch.remoteTarget == nil ? .tertiary : .secondary)
                            .help(branch.remoteTarget.map {
                                "This branch will be deleted when remote deletion is enabled: \($0.fullPath)"
                            } ?? "No unambiguous matching remote branch")
                    }
                    .width(min: 150, ideal: 210)
                }

                Toggle("Select all branches", sources: $branches, isOn: \.isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(branches.isEmpty)
                    .accessibilityLabel("Select all branches")
                    .help("Select or deselect all branches")
                    .padding(.leading, 12)
                    .padding(.top, 5)
            }
            .frame(height: 320)
        }
    }

    // MARK: - Actions

    private func createBranch() async {
        do {
            let startReference = branchStartReference()
            let support = GitBranchUndoSupport()
            let startPoint = try await support.tip(of: startReference ?? "HEAD", in: repositoryURL)
            _ = try await GitStatusService.shared.createBranch(
                name: sanitizedName,
                checkout: checkoutNewBranch,
                commit: startReference,
                in: repositoryURL
            )
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Create branch \(sanitizedName)",
                        undoOperation: .deleteLocalBranch(name: sanitizedName, force: true, expectedTip: startPoint),
                        redoOperation: .createLocalBranch(name: sanitizedName, startPoint: startPoint, checkout: checkoutNewBranch)
                    )
                )
                onCompleted()
                dismiss()
                if checkoutNewBranch && commitAllChanges {
                    onCommitAllChangesRequested?()
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func deleteSelectedBranches() async {
        await MainActor.run {
            isDeleting = true
        }

        let selection = selectedBranches
        let remoteTargets: [String: RemoteBranchDeleteTarget] = deleteMatchingRemoteBranches
            ? Dictionary(
                selection.compactMap { item in
                    item.type == .local ? item.remoteTarget.map { (item.name, $0) } : nil
                },
                uniquingKeysWith: { first, _ in first }
            )
            : [:]
        let result = await GitStatusService.shared.deleteLocalBranches(
            GitLocalBranchDeletionRequest(
                branches: selection.filter { $0.type == .local }.map(\.name),
                force: forceDelete,
                currentBranch: currentBranch,
                remoteTargets: remoteTargets
            ),
            validate: validateLocalBranchDeletion,
            in: repositoryURL
        )

        // Remote targets of failed local deletes are skipped; directly selected remotes always run.
        var pending = result.deleted.compactMap { local in
            local.remoteTarget.map { GitPendingRemoteBranchDeletion(target: $0, localBranch: local) }
        }
        let pendingTargets = Set(pending.map(\.target))
        for item in selection where item.type == .remote {
            guard let target = RemoteBranchDeleteTarget(fullPath: item.name),
                  !pendingTargets.contains(target) else { continue }
            pending.append(GitPendingRemoteBranchDeletion(target: target, localBranch: nil))
        }

        let didDeleteBranch = !result.deleted.isEmpty || !pending.isEmpty
        await MainActor.run {
            for local in result.deleted where local.remoteTarget == nil {
                undoManager?.register(
                    GitBranchUndoSupport.deletedBranchUndoEntry(
                        repositoryURL: repositoryURL,
                        branch: local.name,
                        force: local.force,
                        tip: local.tip,
                        upstream: local.upstream,
                        remoteTarget: nil,
                        remoteHash: nil
                    )
                )
            }
            if !pending.isEmpty {
                onRunBackgroundRemoteBranchDeletion(pending)
            }
            if didDeleteBranch { onCompleted() }
        }

        guard !result.failures.isEmpty else {
            await MainActor.run {
                isDeleting = false
                showingDeleteConfirmation = false
                dismiss()
            }
            return
        }

        if didDeleteBranch {
            await loadDeleteData()
        }
        await MainActor.run {
            isDeleting = false
            showingDeleteConfirmation = false
            errorMessage = GitStatusService.branchDeletionSummary(
                deletedCount: result.deleted.count,
                failures: result.failures
            )
            showingError = true
        }
    }

    // MARK: - Data Loading

    private func loadCreateData() async {
        let branch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        let commits = await GitStatusService.shared.recentCommits(limit: 50, in: repositoryURL)

        await MainActor.run {
            currentBranch = branch
            recentCommits = commits.map { BranchCommitInfo(hash: $0.hash, message: $0.message) }
            if !hasAppliedInitialCreateState {
                let state = Self.initialCreateState(
                    initialStartPoint: initialStartPoint,
                    recentCommits: recentCommits
                )
                useWorkingCopyParent = state.useWorkingCopyParent
                selectedStartPoint = state.selectedStartPoint
                selectedStartReference = state.selectedStartReference
                if case .commit(let hash, let message) = state.selectedStartPoint {
                    let selectedCommit = BranchCommitInfo(hash: hash, message: message)
                    startPointCommitIDInput = hash
                    resolvedStartPointCommit = selectedCommit
                    hasResolvedStartPointCommitID = false
                }
                hasAppliedInitialCreateState = true
            } else if selectedStartReference.isEmpty {
                selectedStartReference = recentCommits.first?.hash ?? ""
            }
        }
    }

    private func loadDeleteData() async {
        let locals = await GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
        let remotesList = await GitStatusService.shared.remotes(in: repositoryURL)
        let initialSelection = hasAppliedInitialDeleteSelection ? [] : initiallySelectedLocalBranches

        var remoteBranchesByRemote: [String: [String]] = [:]
        for remote in remotesList {
            remoteBranchesByRemote[remote] = await GitStatusService.shared.cachedRemoteBranches(
                remote: remote,
                in: repositoryURL
            ).filter { $0 != "HEAD" }
        }

        var items: [BranchDeleteItem] = []

        for name in locals {
            if let localBranchFilter, !localBranchFilter.contains(name) { continue }
            let upstream = await GitBranchUndoSupport().upstream(of: name, in: repositoryURL)
            items.append(
                BranchDeleteItem(
                    name: name,
                    type: .local,
                    remoteTarget: RemoteBranchDeleteResolver.target(
                        localBranch: name,
                        upstream: upstream,
                        branchesByRemote: remoteBranchesByRemote
                    ),
                    isSelected: initialSelection.contains(name)
                )
            )
        }

        for remote in remotesList {
            guard localBranchFilter == nil else { continue }
            for branchName in remoteBranchesByRemote[remote] ?? [] {
                items.append(BranchDeleteItem(name: "\(remote)/\(branchName)", type: .remote))
            }
        }

        await MainActor.run {
            branches = items
            hasAppliedInitialDeleteSelection = true
        }
    }

    // MARK: - Helpers

    @MainActor
    static func initialCreateState(
        initialStartPoint: GitBranchStartPoint?,
        recentCommits: [BranchCommitInfo]
    ) -> InitialCreateState {
        switch initialStartPoint {
        case nil:
            return InitialCreateState(
                useWorkingCopyParent: true,
                selectedStartPoint: nil,
                selectedStartReference: recentCommits.first?.hash ?? ""
            )
        case .commit(let hash, let message):
            let selectedCommit = recentCommits.first(where: { $0.hash == hash })
                ?? BranchCommitInfo(hash: hash, message: message)
            return InitialCreateState(
                useWorkingCopyParent: false,
                selectedStartPoint: .commit(hash: selectedCommit.hash, message: selectedCommit.message),
                selectedStartReference: selectedCommit.hash
            )
        case .branch(let name):
            return InitialCreateState(
                useWorkingCopyParent: false,
                selectedStartPoint: .branch(name),
                selectedStartReference: name
            )
        }
    }

    static func commitPickerOptions(
        selectedStartPoint: GitBranchStartPoint?,
        recentCommits: [BranchCommitInfo]
    ) -> [BranchCommitInfo] {
        guard let selectedStartPoint else {
            return recentCommits
        }

        switch selectedStartPoint {
        case .commit(let hash, let message):
            guard recentCommits.contains(where: { $0.hash == hash }) == false else {
                return recentCommits
            }
            return [BranchCommitInfo(hash: hash, message: message)] + recentCommits
        case .branch(let name):
            guard recentCommits.contains(where: { $0.hash == name }) == false else {
                return recentCommits
            }
            return [BranchCommitInfo(hash: name, message: "Branch")] + recentCommits
        }
    }

    private func resolveStartPointCommitID() async {
        let input = startPointCommitIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            isResolvingStartPointCommit = true
            resolvedStartPointCommit = nil
            hasResolvedStartPointCommitID = false
            startPointCommitIDError = nil
        }

        let resolved = await GitStatusService.shared.commitInfoIncludingRemotes(for: input, in: repositoryURL)
        await MainActor.run {
            guard startPointCommitIDInput.trimmingCharacters(in: .whitespacesAndNewlines) == input else {
                return
            }
            isResolvingStartPointCommit = false
            guard let resolved else {
                selectedStartPoint = nil
                selectedStartReference = ""
                startPointCommitIDError = input.isEmpty
                    ? "Enter a commit ID."
                    : "Commit not found."
                return
            }

            let commit = BranchCommitInfo(hash: resolved.hash, message: resolved.message)
            resolvedStartPointCommit = commit
            hasResolvedStartPointCommitID = true
            selectedStartReference = commit.hash
            selectedStartPoint = .commit(hash: commit.hash, message: commit.message)
        }
    }

    private func branchStartReference() -> String? {
        guard !useWorkingCopyParent else { return nil }
        switch selectedStartPoint {
        case .commit(let hash, _):
            return hash
        case .branch(let name):
            return name
        case nil:
            return selectedStartReference.isEmpty ? nil : selectedStartReference
        }
    }
}

#Preview {
    BranchSheetView(repositoryURL: URL(fileURLWithPath: "/tmp"), onRunBackgroundRemoteBranchDeletion: { _ in }) {}
}
