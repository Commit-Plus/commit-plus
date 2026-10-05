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

struct CreateWorktreeSheet: View {
    @Binding var mode: WorktreeCreationMode
    let availableBranches: [String]
    @Binding var selectedExistingBranch: String
    @Binding var newBranchName: String
    @Binding var newBaseBranch: String
    @Binding var path: String
    @Binding var label: String
    @Binding var openAfterCreate: Bool
    let errorMessage: String?
    let canCreate: Bool
    let isCreating: Bool
    let onModeChange: () -> Void
    let onSelectedExistingBranchChange: () -> Void
    let onNewBranchNameChange: () -> Void
    let onPathChange: (String) -> Void
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Worktree")
                .font(.title2)
                .fontWeight(.semibold)

            Picker("", selection: $mode) {
                ForEach(WorktreeCreationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in
                onModeChange()
            }

            if mode == .existingBranch {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch:")
                        .font(.system(size: 13))
                    SearchableReferencePicker(
                        title: "Worktree branch", selection: selectedExistingBranch,
                        options: availableBranches, searchPrompt: "Search branches",
                        onSelect: { selectedExistingBranch = $0 })
                    .pickerStyle(.menu)
                    .onChange(of: selectedExistingBranch) { _, _ in
                        onSelectedExistingBranchChange()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New branch name:")
                        .font(.system(size: 13))
                    TextField("feature/worktree-task", text: $newBranchName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newBranchName) { _, _ in
                            onNewBranchNameChange()
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Base branch:")
                        .font(.system(size: 13))
                    SearchableReferencePicker(
                        title: "Base branch", selection: newBaseBranch,
                        options: availableBranches, searchPrompt: "Search branches",
                        onSelect: { newBaseBranch = $0 })
                    .pickerStyle(.menu)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Path:")
                    .font(.system(size: 13))
                TextField("", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: path) { _, newValue in
                        onPathChange(newValue)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Label (optional):")
                    .font(.system(size: 13))
                TextField("Task label", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Open after create", isOn: $openAfterCreate)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

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
                    .disabled(isCreating)

                Button("Create Worktree", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || isCreating)
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 500)
    }
}
