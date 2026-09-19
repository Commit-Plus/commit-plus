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

struct EditSubmoduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: GitSubmoduleEntry
    let onSave: @MainActor (_ url: String, _ branch: String?) async throws -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State private var repositoryURL: String
    @State private var branch: String
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(
        entry: GitSubmoduleEntry,
        onSave: @escaping @MainActor (_ url: String, _ branch: String?) async throws -> Void,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onRunRepositoryOperation = onRunRepositoryOperation
        _repositoryURL = State(initialValue: entry.url)
        _branch = State(initialValue: entry.branch ?? "")
    }

    private var trimmedRepositoryURL: String {
        repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBranch: String? {
        let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var canSave: Bool {
        !trimmedRepositoryURL.isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Submodule Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                fieldRow(title: "Path") {
                    Text(entry.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                fieldRow(title: "Repository URL") {
                    TextField("https://github.com/user/repo.git", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                fieldRow(title: "Branch") {
                    TextField("Optional", text: $branch)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)

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
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 600)
        .frame(minHeight: 220, idealHeight: 280)
        .onChange(of: repositoryURL) { _, _ in
            if !isLoading {
                errorMessage = trimmedRepositoryURL.isEmpty ? "Enter a submodule repository URL." : nil
            }
        }
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
        guard canSave else {
            errorMessage = "Enter a submodule repository URL."
            return
        }

        isLoading = true
        errorMessage = nil
        let url = trimmedRepositoryURL
        let branch = trimmedBranch
        onRunRepositoryOperation("Saving submodule \(entry.path)...") {
            do {
                try await onSave(url, branch)
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
