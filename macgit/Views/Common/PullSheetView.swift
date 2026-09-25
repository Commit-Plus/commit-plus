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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Remote repository
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pull from repository:")
                            .font(.system(size: 13))
                        Picker("", selection: $selectedRemote) {
                            ForEach(remotes, id: \.self) { remote in
                                Text(remote).tag(remote)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedRemote) { _, newValue in
                            guard !isLoading else { return }
                            Task {
                                await loadRemoteURL(remote: newValue)
                                await loadRemoteBranches(remote: newValue)
                            }
                        }

                        if !remoteURL.isEmpty {
                            Text(remoteURL)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // Remote branch
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remote branch to pull:")
                                .font(.system(size: 13))
                            HStack(spacing: 8) {
                                Picker("", selection: $selectedBranch) {
                                    Text("Select a branch").tag("")
                                    ForEach(remoteBranches, id: \.self) { branch in
                                        Text(branch).tag(branch)
                                    }
                                }
                                .pickerStyle(.menu)

                                Button("Refresh") {
                                    Task { await loadRemoteBranches(remote: selectedRemote) }
                                }
                                .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
                            }
                        }
                    }

                    // Local branch
                    HStack(spacing: 12) {
                        Text("Pull into local branch:")
                            .font(.system(size: 13))
                        Text(localBranch)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }

                    // Options
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Options")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.bottom, 2)

                        Toggle("Commit merged changes immediately", isOn: $commitMerged)
                            .font(.system(size: 12))

                        Toggle("Include messages from commits being merged in merge commit", isOn: $includeMessages)
                            .font(.system(size: 12))

                        Toggle("Create new commit even if fast-forward merge", isOn: $noFastForward)
                            .font(.system(size: 12))

                        Toggle("Rebase instead of merge (WARNING: make sure you haven't pushed your changes)", isOn: $rebaseInstead)
                            .font(.system(size: 12))
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(24)
            }

            // Buttons
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    dismiss()
                    onPull(selectedRemote, selectedBranch, pullOptions)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(isLoading || selectedRemote.isEmpty || selectedBranch.isEmpty)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520)
        .frame(minHeight: 420, idealHeight: 460)
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
