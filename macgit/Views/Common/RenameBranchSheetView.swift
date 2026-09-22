//
//  RenameBranchSheetView.swift
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

struct RenameBranchSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let currentName: String
    let undoManager: GitUndoManager?
    var onRunRepositoryOperation: RepositoryOperationRunner = { _, operation in
        Task { await operation() }
    }
    let onCompleted: () -> Void

    @State private var newName: String
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(
        repositoryURL: URL,
        currentName: String,
        undoManager: GitUndoManager?,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner = { _, operation in
            Task { await operation() }
        },
        onCompleted: @escaping () -> Void
    ) {
        self.repositoryURL = repositoryURL
        self.currentName = currentName
        self.undoManager = undoManager
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.onCompleted = onCompleted
        _newName = State(initialValue: currentName)
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        let trimmed = trimmedNewName
        return !trimmed.isEmpty && trimmed != currentName
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rename Branch")
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Current name")
                            .font(.system(size: 13))
                            .frame(width: 100, alignment: .trailing)

                        Text(currentName)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("New name")
                            .font(.system(size: 13))
                            .frame(width: 100, alignment: .trailing)

                        TextField("branch-name", text: $newName)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 112)
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .frame(maxWidth: 420, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    onRunRepositoryOperation("Renaming \(currentName)...") {
                        await save()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!isValid || isLoading)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 520)
        .frame(minHeight: 200, idealHeight: 220)
    }

    private func save() async {
        guard isValid else { return }
        let target = trimmedNewName
        isLoading = true
        do {
            _ = try await GitStatusService.shared.renameBranch(
                from: currentName,
                to: target,
                in: repositoryURL
            )
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Rename branch \(currentName) → \(target)",
                        undoOperation: .renameLocalBranch(from: target, to: currentName),
                        redoOperation: .renameLocalBranch(from: currentName, to: target)
                    )
                )
                onCompleted()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    RenameBranchSheetView(
        repositoryURL: URL(fileURLWithPath: "/tmp"),
        currentName: "main",
        undoManager: nil,
        onCompleted: {}
    )
}
