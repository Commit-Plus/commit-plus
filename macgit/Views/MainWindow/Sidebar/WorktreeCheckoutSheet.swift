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

struct WorktreeCheckoutSheet: View {
    let entry: WorktreeEntry
    let branches: [String]
    @Binding var selection: String
    let errorMessage: String?
    let canCheckout: Bool
    let isCheckingOut: Bool
    let onCancel: () -> Void
    let onCheckout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Switch Worktree Branch")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Worktree:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(entry.path.path)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Branch:")
                    .font(.system(size: 13))
                SearchableReferencePicker(
                    title: "Worktree branch", selection: selection,
                    options: branches, searchPrompt: "Search branches",
                    onSelect: { selection = $0 })
                .pickerStyle(.menu)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCheckingOut)

                Button("Switch", action: onCheckout)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCheckout || isCheckingOut)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
    }
}
