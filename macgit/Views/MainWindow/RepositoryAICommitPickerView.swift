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

struct RepositoryAICommitPickerView: View {
    @ObservedObject var controller: RepositoryAIChatController
    let onSelectCommit: (RepositoryAICommitChoice) -> Void
    let onSubmitReference: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: controller.cancelCommitSelection)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .foregroundStyle(.secondary)
                    .disabled(controller.isLoadingCommits)

                Text("Choose a commit")
                    .font(.headline)
            }

            Text("Select one of the 10 latest commits, or enter any commit ID, branch, or tag.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Commit ID, branch, or tag", text: $controller.commitReferenceDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(controller.isLoadingCommits || controller.isRunning)
                    .onSubmit(onSubmitReference)

                Button("Explain commit", systemImage: "arrow.right", action: onSubmitReference)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .pointingHandCursor()
                    .disabled(!controller.canExplainCommitReference)
            }

            if controller.isLoadingCommits {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading recent commits…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if controller.recentCommits.isEmpty {
                ContentUnavailableView(
                    "No commits found",
                    systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                    description: Text("Enter a commit ID above to continue.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(controller.recentCommits) { commit in
                            Button(action: { onSelectCommit(commit) }) {
                                HStack(spacing: 8) {
                                    Text(commit.hash)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Color.accentColor)
                                    Text(commit.subject)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .disabled(controller.isRunning)
                            .help("Explain commit \(commit.hash): \(commit.subject)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
