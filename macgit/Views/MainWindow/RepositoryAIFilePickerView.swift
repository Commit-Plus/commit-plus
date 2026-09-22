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

struct RepositoryAIFilePickerView: View {
    @ObservedObject var controller: RepositoryAIChatController
    let onSelect: (RepositoryAIFileReference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Review changed file", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: controller.cancelFileSelection)
                    .pointingHandCursor()
                    .controlSize(.small)
            }
            Text("Choose a bounded, read-only file context. Staged and working-tree versions remain separate.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if controller.isLoadingFiles {
                ProgressView("Loading changed files…")
                    .controlSize(.small)
            } else if controller.changedFiles.isEmpty {
                ContentUnavailableView("No eligible changed files", systemImage: "doc")
            } else {
                List(controller.changedFiles) { file in
                    Button(action: { onSelect(file) }) {
                        HStack(spacing: 8) {
                            Image(systemName: file.source == .index ? "checkmark.circle" : "pencil.circle")
                                .foregroundStyle(file.source == .index ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.path).lineLimit(1)
                                Text(file.source.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .accessibilityLabel("Review \(file.source.displayName) file \(file.path)")
                }
                .listStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
