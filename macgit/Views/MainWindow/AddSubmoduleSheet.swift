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

struct AddSubmoduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let onAdd: (SubmoduleAddRequest) async throws -> Void
    let onCompleted: (SubmoduleAddRequest) -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State private var repository = ""
    @State private var path = ""
    @State private var branch = ""
    @State private var initializeAfterAdd = true
    @State private var shallow = false
    @State private var force = false
    @State private var showingInitializeHelp = false
    @State private var showingShallowHelp = false
    @State private var showingForceHelp = false
    @State private var isLoading = false
    @State private var isValid = false
    @State private var errorMessage: String?

    private var validationKey: String {
        [
            repository,
            path,
            branch,
            initializeAfterAdd ? "1" : "0",
            shallow ? "1" : "0",
            force ? "1" : "0"
        ].joined(separator: "|")
    }

    private var canAdd: Bool {
        isValid && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add Submodule")
                        .font(.title2)
                        .fontWeight(.semibold)

                    fieldRow(title: "Repository URL") {
                        inputWithPicker {
                            TextField("https://github.com/user/repo.git", text: $repository)
                                .disableAutocorrection(true)
                        } action: {
                            chooseRepositoryFolder()
                        }
                    }

                    fieldRow(title: "Local Folder") {
                        inputWithPicker {
                            TextField("Packages/SharedKit", text: $path)
                                .disableAutocorrection(true)
                        } action: {
                            chooseLocalFolder()
                        }
                    }

                    fieldRow(title: "Branch") {
                        TextField("Optional", text: $branch)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        optionRow(
                            title: "Initialize after adding",
                            isOn: $initializeAfterAdd,
                            showingHelp: $showingInitializeHelp,
                            helpTitle: "Initialize after adding",
                            helpText: "When enabled, the submodule is cloned and checked out immediately. When disabled, its configuration is added but the working copy stays uninitialized until you run Initialize."
                        )
                        optionRow(
                            title: "Shallow clone",
                            isOn: $shallow,
                            showingHelp: $showingShallowHelp,
                            helpTitle: "Shallow clone",
                            helpText: "When enabled, only the latest commit is cloned (depth 1), making the operation faster and smaller. Older history is not available until you fetch it later."
                        )
                    }
                    .font(.system(size: 13))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: 520, alignment: .leading)
            }

            HStack(spacing: 12) {
                optionRow(
                    title: "Force",
                    isOn: $force,
                    showingHelp: $showingForceHelp,
                    helpTitle: "Force add",
                    helpText: "When enabled, passes --force to git submodule add, reusing the local git directory if one already exists for this path (for example after removing and re-adding the same submodule). It does not bypass nesting conflicts."
                )
                .font(.system(size: 13))
                .disabled(isLoading)

                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isLoading)

                Button(isLoading ? "Adding..." : "Add Submodule") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!canAdd)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 600)
        .frame(minHeight: 280, idealHeight: 340)
        .task(id: validationKey) {
            refreshValidation()
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

    private func optionRow(
        title: String,
        isOn: Binding<Bool>,
        showingHelp: Binding<Bool>,
        helpTitle: String,
        helpText: String
    ) -> some View {
        HStack(spacing: 6) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)

            Button {
                showingHelp.wrappedValue.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(helpText)
            .accessibilityLabel("Help for (helpTitle)")
            .popover(isPresented: showingHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(helpTitle)
                        .font(.headline)
                    Text(helpText)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(width: 300, alignment: .leading)
            }
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
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = repositoryURL
        panel.message = "Select a folder inside the current repository"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        path = SubmoduleRequestValidator.relativePath(for: url, in: repositoryURL) ?? url.path
    }

    private func refreshValidation() {
        do {
            _ = try validatedRequest()
            isValid = true
            if !isLoading {
                errorMessage = nil
            }
        } catch {
            isValid = false
            if !isLoading {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func validatedRequest() throws -> SubmoduleAddRequest {
        try SubmoduleRequestValidator.validate(
            addRequest: SubmoduleAddRequest(
                repository: repository,
                path: path,
                branch: branch,
                initializeAfterAdd: initializeAfterAdd,
                shallow: shallow,
                force: force
            ),
            in: repositoryURL
        )
    }

    private func submit() {
        guard !isLoading else { return }

        do {
            let request = try validatedRequest()
            isLoading = true
            errorMessage = nil
            onRunRepositoryOperation("Adding submodule \(request.path)...") {
                do {
                    try await onAdd(request)
                    await MainActor.run {
                        onCompleted(request)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
