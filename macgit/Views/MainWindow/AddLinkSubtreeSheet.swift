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
import AppKit
import SwiftUI

private enum SubtreeSheetMode: String, CaseIterable, Identifiable {
    case linkExisting = "Link Existing"
    case addNew = "Add New"

    var id: String { rawValue }
}

struct AddLinkSubtreeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let onAdd: (SubtreeLinkRequest) async throws -> GitSubtreeEntry
    let onLink: (SubtreeLinkRequest) async throws -> GitSubtreeEntry
    let onCompleted: (GitSubtreeEntry) -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State private var mode: SubtreeSheetMode = .addNew
    @State private var name = ""
    @State private var path = ""
    @State private var repository = ""
    @State private var branch = "main"
    @State private var squash = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
    }

    private var submitTitle: String {
        switch mode {
        case .addNew: "Add Subtree"
        case .linkExisting: "Link Subtree"
        }
    }

    private var loadingTitle: String {
        switch mode {
        case .addNew: "Adding..."
        case .linkExisting: "Linking..."
        }
    }

    private var progressMessage: String {
        switch mode {
        case .addNew: "Adding subtree..."
        case .linkExisting: "Linking subtree \(path)..."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add/Link Subtree")
                    .font(.title2)
                    .fontWeight(.semibold)

                Picker("Mode", selection: $mode) {
                    ForEach(SubtreeSheetMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                fieldRow(title: "Name") {
                    TextField("SharedKit", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                fieldRow(title: "Local folder") {
                    inputWithPicker {
                        TextField("Packages/SharedKit", text: $path)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                    } action: {
                        chooseLocalFolder()
                    }
                }

                fieldRow(title: "Repository URL") {
                    inputWithPicker {
                        TextField("https://github.com/user/repo.git", text: $repository)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                    } action: {
                        chooseRepositoryFolder()
                    }
                }

                fieldRow(title: "Branch") {
                    TextField("main", text: $branch)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }

                Toggle("Squash imported history", isOn: $squash)
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

                Button(isLoading ? loadingTitle : submitTitle) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!canSubmit)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 540, idealWidth: 580, maxWidth: 640)
        .frame(minHeight: 360, idealHeight: 440)
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

    private func inputWithPicker<Content: View>(
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            content()
                .textFieldStyle(.roundedBorder)

            Button("…", action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Choose folder")
        }
    }

    private func chooseRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = repositoryURL.deletingLastPathComponent()
        panel.message = "Select a local Git repository"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        repository = url.path
    }

    private func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = mode == .addNew
        panel.allowsMultipleSelection = false
        panel.directoryURL = repositoryURL
        panel.message = "Select a folder inside the current repository"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        path = SubmoduleRequestValidator.relativePath(for: url, in: repositoryURL) ?? url.path
    }

    private func submit() {
        guard canSubmit else { return }

        let request = SubtreeLinkRequest(
            name: name,
            path: path,
            repository: repository,
            branch: branch,
            squash: squash
        )
        isLoading = true
        errorMessage = nil
        onRunRepositoryOperation(progressMessage) {
            do {
                let entry: GitSubtreeEntry
                switch mode {
                case .addNew:
                    entry = try await onAdd(request)
                case .linkExisting:
                    entry = try await onLink(request)
                }
                await MainActor.run {
                    onCompleted(entry)
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = sanitizedErrorMessage(error.localizedDescription)
                    isLoading = false
                }
            }
        }
    }

    private func sanitizedErrorMessage(_ message: String) -> String {
        let lines = message
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let limited = lines.prefix(8).joined(separator: "\n")
        return limited.isEmpty ? "The subtree operation failed." : limited
    }
}
