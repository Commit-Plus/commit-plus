//
//  PushSheetView.swift
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

struct BranchPushInfo: Identifiable {
    let id = UUID()
    let local: String
    var remote: String
    var isSelected: Bool
    var isTracked: Bool
}

enum PushRemoteSelectionPolicy {
    static func resolve(
        remotes: [String],
        currentBranch: String?,
        upstreams: [String: String]
    ) -> String {
        guard let currentBranch,
              let upstream = upstreams[currentBranch] else {
            return remotes.first ?? ""
        }

        return remotes
            .sorted { $0.count > $1.count }
            .first { upstream.hasPrefix("\($0)/") }
            ?? remotes.first
            ?? ""
    }
}

enum BranchPushInfoBuilder {
    static func build(
        localBranches: [String],
        upstreams: [String: String],
        currentBranch: String,
        remoteBranches: Set<String> = [],
        defaultBranch: String? = nil,
        selectedRemote: String? = nil
    ) -> [BranchPushInfo] {
        let prioritizedBranches = localBranches.sorted { lhs, rhs in
            func rank(_ branch: String) -> Int {
                if branch == currentBranch { return 0 }
                if branch == defaultBranch { return 1 }
                return 2
            }
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return prioritizedBranches.map { branch in
            let upstream = upstreams[branch].flatMap { value in
                guard let selectedRemote else { return value }
                return value.hasPrefix("\(selectedRemote)/") ? value : nil
            }
            let isTracked = upstream != nil
            let upstreamRemoteName = upstream?.components(separatedBy: "/").dropFirst().joined(separator: "/")
            let resolvedRemote: String
            if let upstreamRemoteName, !upstreamRemoteName.isEmpty {
                resolvedRemote = upstreamRemoteName
            } else if remoteBranches.contains(branch) {
                resolvedRemote = branch
            } else {
                resolvedRemote = ""
            }
            return BranchPushInfo(
                local: branch,
                remote: resolvedRemote,
                isSelected: branch == currentBranch && !resolvedRemote.isEmpty,
                isTracked: isTracked
            )
        }
    }
}

struct PushSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let repositoryURL: URL
    var onForcePush: ((String, String, String) -> Void)? = nil
    let onPush: (GitStatusService.PushOptions) -> Void

    @State private var remotes: [String] = []
    @State private var selectedRemote: String = ""
    @State private var remoteURL: String = ""

    @State private var branches: [BranchPushInfo] = []
    @State private var selectAll: Bool = false
    @State private var pushTags: Bool = false

    @State private var isLoading = false
    @State private var isSubmitting = false

    private var selectedBranches: [BranchPushInfo] {
        branches.filter { $0.isSelected }
    }

    private var canPush: Bool {
        !selectedBranches.isEmpty && !selectedRemote.isEmpty && !isSubmitting && !isLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Remote repository
            VStack(alignment: .leading, spacing: 4) {
                Text("Push to repository:")
                    .font(.system(size: 13))
                HStack(spacing: 8) {
                    Picker("", selection: $selectedRemote) {
                        ForEach(remotes, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedRemote) { _, newValue in
                        branches = []
                        remoteURL = ""
                        isLoading = true
                        Task {
                            await loadRemoteURL(remote: newValue)
                            await loadBranches(remote: newValue)
                        }
                    }

                    if !remoteURL.isEmpty {
                        Text(remoteURL)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Branches to push
            VStack(alignment: .leading, spacing: 8) {
                Text("Branches to push")
                    .font(.system(size: 13, weight: .semibold))

                // Header row
                HStack(spacing: 0) {
                    Text("Push")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 40, alignment: .leading)
                    Text("Local branch")
                        .font(.system(size: 11, weight: .medium))
                        .frame(minWidth: 120, alignment: .leading)
                    Spacer()
                    Text("Remote branch")
                        .font(.system(size: 11, weight: .medium))
                        .frame(minWidth: 100, alignment: .leading)
                    Text("Track?")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 50, alignment: .center)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.3))

                // Branch rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($branches) { $branch in
                            HStack(spacing: 0) {
                                Toggle("", isOn: Binding(
                                    get: { branch.isSelected },
                                    set: { newValue in
                                        branch.isSelected = newValue
                                        if newValue && branch.remote.isEmpty {
                                            branch.remote = branch.local
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .frame(width: 40, alignment: .leading)

                                Text(branch.local)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

                                Spacer()

                                if !branch.remote.isEmpty {
                                    Text(branch.remote)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text("—")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                        .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                }

                                if branch.isTracked {
                                    Button(action: {}) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 50)
                                    .disabled(true)
                                } else {
                                    Button(action: {
                                        Task { await setUpstream(for: branch.local) }
                                    }) {
                                        Image(systemName: "arrow.up.arrow.down.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 50)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(branch.isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                        }
                    }
                }
                .frame(minHeight: 240)

                // Select All
                HStack {
                    Toggle("Select All", isOn: Binding(
                        get: { selectAll },
                        set: { newValue in
                            selectAll = newValue
                            for index in branches.indices {
                                branches[index].isSelected = newValue
                                if newValue && branches[index].remote.isEmpty {
                                    branches[index].remote = branches[index].local
                                }
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            .padding(12)
            .background(.quaternary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)

            // Push all tags
            Toggle("Push all tags", isOn: $pushTags)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            // Buttons
            HStack(spacing: 12) {
                if let onForcePush {
                    Button("Force Push…", role: .destructive) {
                        guard let branch = selectedBranches.first, selectedBranches.count == 1 else { return }
                        onForcePush(branch.local, selectedRemote, branch.remote.isEmpty ? branch.local : branch.remote)
                        dismiss()
                    }
                    .disabled(selectedBranches.count != 1 || selectedRemote.isEmpty || isSubmitting || isLoading)
                    .help("Review and force-push the selected branch only. Tags are not included.")
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await performPushIfNeeded() }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("OK")
                    }
                    .frame(minWidth: 40)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!canPush)
            }
            .padding([.horizontal, .bottom], 24)
            .padding(.top, 16)
        }
        .frame(minWidth: 640, idealWidth: 680, maxWidth: 720)
        .frame(minHeight: 480, idealHeight: 540)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        async let remotesTask = GitStatusService.shared.remotes(in: repositoryURL)
        async let currentBranchTask = GitStatusService.shared.currentBranch(in: repositoryURL)
        async let upstreamsTask = GitStatusService.shared.localBranchUpstreams(in: repositoryURL)
        let (currentRemotes, currentBranch, upstreams) = await (
            remotesTask,
            currentBranchTask,
            upstreamsTask
        )
        let currentRemote = PushRemoteSelectionPolicy.resolve(
            remotes: currentRemotes,
            currentBranch: currentBranch,
            upstreams: upstreams
        )

        await MainActor.run {
            remotes = currentRemotes
            selectedRemote = currentRemote
        }

        if !currentRemote.isEmpty {
            await loadRemoteURL(remote: currentRemote)
        }
        await loadBranches(remote: currentRemote)
    }

    private func loadBranches(remote: String) async {
        isLoading = true
        defer { if selectedRemote == remote { isLoading = false } }
        async let branchesTask = GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
        async let currentBranchTask = GitStatusService.shared.currentBranch(in: repositoryURL)
        async let upstreamsTask = GitStatusService.shared.localBranchUpstreams(in: repositoryURL)
        async let defaultBranchTask = remote.isEmpty ? nil : GitStatusService.shared.defaultBranch(in: repositoryURL, remote: remote)

        let currentBranches = await branchesTask
        let currentBranch = await currentBranchTask ?? ""
        let upstreams = await upstreamsTask
        let defaultBranch = await defaultBranchTask

        let remoteBranchNames = remote.isEmpty
            ? []
            : await GitStatusService.shared.cachedRemoteBranches(remote: remote, in: repositoryURL)

        let branchInfos = BranchPushInfoBuilder.build(
            localBranches: currentBranches,
            upstreams: upstreams,
            currentBranch: currentBranch,
            remoteBranches: Set(remoteBranchNames),
            defaultBranch: defaultBranch,
            selectedRemote: remote
        )

        await MainActor.run {
            guard selectedRemote == remote else { return }
            branches = branchInfos
        }
    }

    private func loadRemoteURL(remote: String) async {
        let url = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        await MainActor.run {
            guard selectedRemote == remote else { return }
            remoteURL = url
        }
    }

    private func setUpstream(for branch: String) async {
        do {
            try await GitStatusService.shared.setUpstream(
                upstream: "\(selectedRemote)/\(branch)",
                branch: branch,
                in: repositoryURL
            )
            await loadData()
        } catch {
            // Silently ignore upstream set failures
        }
    }

    @MainActor
    private func performPushIfNeeded() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let branchSupport = GitBranchUndoSupport()
        let remoteSupport = GitRemoteUndoSupport()

        var branchesToPush: [BranchPushInfo] = []
        for branch in selectedBranches {
            let remoteBranchName = branch.remote.isEmpty ? branch.local : branch.remote
            do {
                let localHash = try await branchSupport.tip(of: branch.local, in: repositoryURL)
                let remoteHash = try await remoteSupport.remoteHash(
                    remote: selectedRemote,
                    branch: remoteBranchName,
                    in: repositoryURL
                )
                if let remoteHash, remoteHash == localHash {
                    continue
                }
            } catch {
                // Pre-flight check failed; keep the branch so git reports the real error.
            }
            branchesToPush.append(branch)
        }

        if branchesToPush.isEmpty && !pushTags {
            dismiss()
            return
        }

        dismiss()
        let mappings = branchesToPush.reduce(into: [:]) { result, branch in
            result[branch.local] = branch.remote
        }
        let options = GitStatusService.PushOptions(
            remote: selectedRemote,
            branches: branchesToPush.map(\.local),
            branchMappings: mappings,
            pushTags: pushTags
        )
        onPush(options)
    }
}

#Preview {
    PushSheetView(repositoryURL: URL(fileURLWithPath: "/tmp")) { _ in }
}
