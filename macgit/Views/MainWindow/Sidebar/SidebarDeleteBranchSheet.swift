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

struct SidebarDeleteBranchSheet: View {
    let branchName: String
    @Binding var forceDelete: Bool
    let remoteBranch: RemoteBranchDeleteTarget?
    @Binding var deleteRemoteBranch: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Branch")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Are you sure you want to delete the branch '\(branchName)'?")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Force delete regardless of merge status", isOn: $forceDelete)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Text("Use \u{201C}git branch -D\u{201D}. Required for branches that are not fully merged; otherwise their commits may become unreachable.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let remoteBranch {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "Also delete remote branch \(remoteBranch.fullPath)",
                        isOn: $deleteRemoteBranch
                    )
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                    Text("This removes the branch from the remote repository for every collaborator.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(forceDelete ? "Force Delete" : "Delete", role: .destructive, action: onDelete)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
    }
}
