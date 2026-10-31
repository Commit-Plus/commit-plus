//
//  RemoteEditSheetView.swift
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

struct RemoteEditSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let repositoryURL: URL
    let mode: RemoteEditMode
    /// Remote name to URL for the repository, used to reject duplicates before running Git.
    var existingRemotes: [String: String] = [:]
    let onSave: (String, String) -> Void

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(mode.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Name")
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .trailing)

                        TextField("origin", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .disabled(mode.isNameEditable == false)
                            .onChange(of: name) { errorMessage = nil }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("URL")
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .trailing)

                        TextField("https://github.com/user/repo.git", text: $url)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: url) { errorMessage = nil }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 92)
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

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(!isValid || isLoading)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 520)
        .frame(minHeight: 220, idealHeight: 240)
        .task {
            if case .edit(let existingName, let existingURL) = mode {
                name = existingName
                url = existingURL
            }
        }
    }

    private func save() {
        guard isValid else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        if let conflict = RemoteEditValidation.conflictMessage(
            name: trimmedName, url: trimmedURL, mode: mode, existingRemotes: existingRemotes
        ) {
            errorMessage = conflict
            return
        }
        onSave(trimmedName, trimmedURL)
        dismiss()
    }
}

enum RemoteEditValidation {
    static func conflictMessage(
        name: String,
        url: String,
        mode: RemoteEditMode,
        existingRemotes: [String: String]
    ) -> String? {
        let editedName: String?
        if case .edit(let existingName, _) = mode {
            editedName = existingName
        } else {
            editedName = nil
            if existingRemotes[name] != nil {
                return "A remote named \"\(name)\" already exists."
            }
        }

        let normalizedURL = normalized(url)
        let duplicate = existingRemotes
            .filter { $0.key != editedName && normalized($0.value) == normalizedURL }
            .map(\.key)
            .sorted()
            .first
        guard let duplicate else { return nil }
        return "Remote \"\(duplicate)\" already uses this URL."
    }

    /// Treats `https://host/repo`, `https://host/repo/`, and `https://host/repo.git` as the same remote.
    static func normalized(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value
    }
}

enum RemoteEditMode: Equatable {
    case add
    case edit(name: String, url: String)

    var title: String {
        switch self {
        case .add:
            return "Add Remote"
        case .edit:
            return "Edit Remote"
        }
    }

    var isNameEditable: Bool {
        switch self {
        case .add:
            return true
        case .edit:
            return false
        }
    }
}

#Preview {
    RemoteEditSheetView(
        repositoryURL: URL(fileURLWithPath: "/tmp"),
        mode: .add
    ) { _, _ in }
}
