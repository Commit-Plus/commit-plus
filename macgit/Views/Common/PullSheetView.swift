//
//  PullSheetView.swift
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

struct PullSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let repositoryURL: URL
    let preselectedRemote: String?
    let preselectedBranch: String?
    let defaultPullStrategy: PullStrategy
    let onPull: (String, String, GitStatusService.PullOptions) -> Void

    @State private var remotes: [String] = []
    @State private var selectedRemote: String = ""
    @State private var remoteURL: String = ""

    @State private var remoteBranches: [String] = []
    @State private var selectedBranch: String = ""

    @State private var localBranch: String = ""
    @State private var upstreamRemote: String?
    @State private var upstreamBranch: String?

    @State private var commitMerged = true
    @State private var includeMessages = true
    @State private var noFastForward = false
    @State private var rebaseInstead = false

    @State private var isLoading = false

    private var pullOptions: GitStatusService.PullOptions {
        GitStatusService.PullOptions(
            commitMerged: commitMerged,
            includeMessages: includeMessages,
            noFastForward: noFastForward,
            rebaseInstead: rebaseInstead
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pull Changes")
                    .font(.title2)
                    .bold()
                Text("Integrate changes from a remote branch into your current branch.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow(alignment: .firstTextBaseline) {
                    Text("Remote:")
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Remote", selection: $selectedRemote) {
                            ForEach(remotes, id: \.self) { remote in
                                Text(remote).tag(remote)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: selectedRemote) { _, newValue in
                            guard !isLoading else { return }
                            Task {
                                await loadRemoteURL(remote: newValue)
                                await loadRemoteBranches(remote: newValue)
                            }
                        }

                        if !remoteURL.isEmpty {
                            Text(remoteURL)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(remoteURL)
                        }
                    }
                    .gridColumnAlignment(.leading)
                }

                GridRow(alignment: .firstTextBaseline) {
                    Text("Remote branch:")
                    HStack(spacing: 8) {
                        SearchableReferencePicker(
                            title: "Remote branch to pull", selection: selectedBranch,
                            options: remoteBranches, searchPrompt: "Search remote branches",
                            onSelect: { selectedBranch = $0 })
                            .buttonStyle(.bordered)
                            .help(selectedBranch)

                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await loadRemoteBranches(remote: selectedRemote) }
                        }
                        .labelStyle(.iconOnly)
                        .help("Refresh remote branches")
                    }
                }

                GridRow(alignment: .firstTextBaseline) {
                    Text("Local branch:")
                    Text(localBranch.isEmpty ? "—" : localBranch)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(localBranch)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Commit merged changes immediately", isOn: $commitMerged)
                    Toggle("Include merged commit messages", isOn: $includeMessages)
                        .help("Include messages from commits being merged in the merge commit")
                    Toggle("Create a merge commit even when fast-forward is possible", isOn: $noFastForward)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Rebase instead of merge", isOn: $rebaseInstead)
                        Text("Only rebase changes you haven’t pushed.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } label: {
                Text("Options")
                    .bold()
            }

            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading branches…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Pull") {
                    dismiss()
                    onPull(selectedRemote, selectedBranch, pullOptions)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || selectedRemote.isEmpty || selectedBranch.isEmpty)
            }
        }
        .font(.body)
        .controlSize(.regular)
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        let currentRemotes = await GitStatusService.shared.remotes(in: repositoryURL)
        let currentLocal = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""

        let upstream = await GitStatusService.shared.upstreamBranch(for: currentLocal, in: repositoryURL)
        let trackedRemote = currentRemotes.sorted { $0.count > $1.count }.first { remote in
            upstream?.hasPrefix(remote + "/") == true
        }

        await MainActor.run {
            upstreamRemote = trackedRemote
            upstreamBranch = trackedRemote.flatMap { remote in
                upstream.map { String($0.dropFirst(remote.count + 1)) }
            }
            remotes = currentRemotes
            selectedRemote = trackedRemote ?? preselectedRemote.flatMap { currentRemotes.contains($0) ? $0 : nil } ?? currentRemotes.first ?? ""
            localBranch = currentLocal
            rebaseInstead = defaultPullStrategy == .rebase
        }

        if !selectedRemote.isEmpty {
            await loadRemoteURL(remote: selectedRemote)
            await loadRemoteBranches(remote: selectedRemote)
        }
    }

    private func loadRemoteURL(remote: String) async {
        let url = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        await MainActor.run {
            guard selectedRemote == remote else { return }
            remoteURL = url
        }
    }

    private func loadRemoteBranches(remote: String) async {
        let branches = await GitStatusService.shared.cachedRemoteBranches(remote: remote, in: repositoryURL)
        await MainActor.run {
            guard selectedRemote == remote else { return }
            remoteBranches = branches
            // Prefer the current branch upstream over repository-wide defaults.
            if remote == upstreamRemote, let upstreamBranch, branches.contains(upstreamBranch) {
                selectedBranch = upstreamBranch
            } else if let preselected = preselectedBranch, branches.contains(preselected) {
                selectedBranch = preselected
            } else if let match = branches.first(where: { $0 == localBranch }) {
                selectedBranch = match
            } else {
                selectedBranch = ""
            }
        }
    }
}
