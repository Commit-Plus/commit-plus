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

struct SearchFileOpenRequest: Identifiable {
    let id = UUID()
    let relativePath: String
    var lineTarget: SearchFileLineTarget? = nil
    let applications: [SearchFileApplication]
}

struct SearchFileOpenSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: SearchFileOpenRequest
    let onOpen: (SearchFileApplication, Bool) -> Void

    @State private var selectedBundleIdentifier: String?
    @State private var rememberChoice = false

    init(
        request: SearchFileOpenRequest,
        onOpen: @escaping (SearchFileApplication, Bool) -> Void
    ) {
        self.request = request
        self.onOpen = onOpen
        _selectedBundleIdentifier = State(initialValue: request.applications.first?.bundleIdentifier)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Open File With")
                    .font(.title2.weight(.semibold))

                Text(request.relativePath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(request.applications) { application in
                        applicationRow(application)
                    }
                }
                .padding(12)
            }
            .frame(minHeight: 180, maxHeight: 320)

            Divider()

            VStack(spacing: 16) {
                Toggle("Remember my choice", isOn: $rememberChoice)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Spacer()

                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Open") {
                        guard let selectedApplication else { return }
                        dismiss()
                        onOpen(selectedApplication, rememberChoice)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                    .disabled(selectedApplication == nil)
                }
            }
            .padding(20)
        }
        .frame(width: 460)
    }

    private var selectedApplication: SearchFileApplication? {
        request.applications.first { $0.bundleIdentifier == selectedBundleIdentifier }
    }

    private func applicationRow(_ application: SearchFileApplication) -> some View {
        let isSelected = selectedBundleIdentifier == application.bundleIdentifier

        return Button {
            selectedBundleIdentifier = application.bundleIdentifier
        } label: {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: application.applicationURL.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(application.applicationURL.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
