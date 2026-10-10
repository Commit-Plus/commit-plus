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
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Fetch from all remotes", isOn: $fetchAllRemotes)
                        .font(.system(size: 13))
                        .toggleStyle(.checkbox)

                    Toggle("Prune tracking branches no longer present on remote(s)", isOn: $pruneBranches)
                        .font(.system(size: 13))
                        .toggleStyle(.checkbox)

                    Toggle("Fetch and store all tags locally", isOn: $fetchTags)
                        .font(.system(size: 13))
                        .toggleStyle(.checkbox)
                }
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(24)

            Spacer()

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    dismiss()
                    onFetch(fetchOptions)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 420, idealWidth: 420, maxWidth: 420)
        .frame(minHeight: 200, idealHeight: 220)
    }
}

#Preview {
    FetchSheetView(repositoryURL: URL(fileURLWithPath: "/tmp")) { _ in }
}
