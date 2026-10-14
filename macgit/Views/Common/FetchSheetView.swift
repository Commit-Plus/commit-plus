//
//  FetchSheetView.swift
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

struct FetchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let repositoryURL: URL
    let onFetch: (GitStatusService.FetchOptions) -> Void

    @State private var fetchAllRemotes = false
    @State private var pruneBranches = false
    @State private var fetchTags = false

    private var fetchOptions: GitStatusService.FetchOptions {
        GitStatusService.FetchOptions(
            fetchAllRemotes: fetchAllRemotes,
            prune: pruneBranches,
            fetchTags: fetchTags
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fetch Changes")
                    .font(.title2)
                    .bold()
                Text("Download remote updates without changing your local branches.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Fetch from all remotes", isOn: $fetchAllRemotes)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Prune deleted remote branches", isOn: $pruneBranches)
                        Text("Remove remote-tracking references that no longer exist on the remote.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }

                    Toggle("Fetch and store all tags locally", isOn: $fetchTags)
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } label: {
                Text("Options")
                    .bold()
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Fetch") {
                    dismiss()
                    onFetch(fetchOptions)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .font(.body)
        .controlSize(.regular)
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    FetchSheetView(repositoryURL: URL(fileURLWithPath: "/tmp")) { _ in }
}
