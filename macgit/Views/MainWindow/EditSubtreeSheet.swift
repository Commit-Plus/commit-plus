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

struct EditSubtreeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: GitSubtreeEntry
    let onSave: @MainActor (GitSubtreeEntry) async throws -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State private var name: String
    @State private var path: String
    @State private var repository: String
    @State private var branch: String
    @State private var squash: Bool
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(
        entry: GitSubtreeEntry,
        onSave: @escaping @MainActor (GitSubtreeEntry) async throws -> Void,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onRunRepositoryOperation = onRunRepositoryOperation
        _name = State(initialValue: entry.name)
        _path = State(initialValue: entry.path)
        _repository = State(initialValue: entry.repository)
        _branch = State(initialValue: entry.branch)
        _squash = State(initialValue: entry.squash)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Subtree Link")
                    .font(.title2)
                    .fontWeight(.semibold)

                fieldRow(title: "Name") {
                    TextField("SharedKit", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                fieldRow(title: "Local folder") {
                    TextField("Packages/SharedKit", text: $path)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                fieldRow(title: "Repository URL") {
                    TextField("https://github.com/user/repo.git", text: $repository)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                fieldRow(title: "Branch") {
                    TextField("main", text: $branch)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                Toggle("Squashed", isOn: $squash)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 540, alignment: .leading)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isLoading)

                Button(isLoading ? "Saving..." : "Save") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!canSave)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 540, idealWidth: 580, maxWidth: 640)
        .frame(minHeight: 320, idealHeight: 400)
    }

    private func fieldRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 132, alignment: .trailing)
            content()
        }
    }

    private func submit() {
        guard canSave else { return }
        let updated = GitSubtreeEntry(
            id: entry.id,
            name: name,
            path: path,
            repository: repository,
            branch: branch,
            squash: squash,
            folderExists: entry.folderExists
        )
        isLoading = true
        errorMessage = nil
        onRunRepositoryOperation("Saving subtree \(entry.path)...") {
            do {
                try await onSave(updated)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

