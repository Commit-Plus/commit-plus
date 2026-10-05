//
//  MergeSheetView.swift
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

struct MergeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let repositoryURL: URL
    let onMerge: (String, String, GitStatusService.MergeOptions) -> Void

    @State private var allBranches: [String] = []
    @State private var selectedBranch: String = ""
    @State private var currentBranch: String = ""

    @State private var noFastForward = false
    @State private var squash = false
    @State private var commitMessage: String = ""

    @State private var isLoading = false

    private var mergeOptions: GitStatusService.MergeOptions {
        GitStatusService.MergeOptions(
            noFastForward: noFastForward,
            squash: squash,
            message: commitMessage
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Source branch
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Source branch:")
                            .font(.system(size: 13))
                        SearchableReferencePicker(
                            title: "Source branch", selection: selectedBranch,
                            options: allBranches, searchPrompt: "Search branches",
                            onSelect: { selectedBranch = $0 })
                        .pickerStyle(.menu)
                    }

                    // Target branch
                    HStack(spacing: 12) {
                        Text("Merge into:")
                            .font(.system(size: 13))
                        Text(currentBranch)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }

                    // Options
                    HStack(spacing: 16) {
                        Toggle("No fast-forward", isOn: $noFastForward)
                            .font(.system(size: 12))

                        Toggle("Squash", isOn: $squash)
                            .font(.system(size: 12))
                    }

                    // Commit message
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Commit message:")
                            .font(.system(size: 13))
                        TextField("", text: $commitMessage)
                            .textFieldStyle(.roundedBorder)
                            .disabled(squash)
                    }
                    .opacity(squash ? 0.5 : 1.0)
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
                    onMerge(selectedBranch, commitMessage, mergeOptions)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(selectedBranch.isEmpty)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520)
        .frame(minHeight: 380, idealHeight: 420)
        .task {
            await loadData()
        }
        .onChange(of: selectedBranch) { _, newValue in
            if !newValue.isEmpty {
                commitMessage = "Merge branch '\(newValue)' into \(currentBranch)"
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        let local = await GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
        let current = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)

        var branches: [String] = local
        for remote in remotes {
            let remoteBranchList = await GitStatusService.shared.cachedRemoteBranches(remote: remote, in: repositoryURL)
            for branch in remoteBranchList {
                branches.append("\(remote)/\(branch)")
            }
        }

        // Remove current branch and duplicates, then sort
        branches = Array(Set(branches)).filter { $0 != current }.sorted()

        await MainActor.run {
            allBranches = branches
            currentBranch = current
            if let first = branches.first {
                selectedBranch = first
            }
        }
    }
}
