//
//  CommitFileListView.swift
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

struct CommitFileListView: View {
    let changes: [CommitFileChange]
    @Binding var selectedFile: CommitFileChange?
    var onPreview: ((CommitFileChange) -> Void)? = nil
    @State private var visibleFileCount = 200
    private let pageSize = 200
    
    var body: some View {
        List(selection: $selectedFile) {
            ForEach(changes.prefix(visibleFileCount)) { change in
                HStack(spacing: 8) {
                    Image(systemName: statusSymbol(for: change.status))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(statusColor(for: change.status))
                        .frame(width: 18, alignment: .center)
                        .help(change.status.displayText)
                        .accessibilityLabel(change.status.displayText)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(fileName(from: change.path))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(directory(from: change.path))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        if let oldPath = change.oldPath {
                            Text("From: \(oldPath)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(oldPath)
                        }
                    }
                    
                    Spacer()
                    
                    if let onPreview {
                        Button("Preview full file", systemImage: "eye") {
                            onPreview(change)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Preview the full file with changes")
                        .accessibilityLabel("Preview \(fileName(from: change.path))")
                        .onContinuousHover { phase in
                            switch phase {
                            case .active: NSCursor.pointingHand.set()
                            case .ended: NSCursor.arrow.set()
                            }
                        }
                    } else {
                        Text(change.status.displayText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(statusColor(for: change.status).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .padding(.vertical, 2)
                .tag(change)
            }
            if visibleFileCount < changes.count {
                Text("Loading more files… (\(visibleFileCount) of \(changes.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
                    .id(visibleFileCount)
                    .onAppear {
                        visibleFileCount = min(visibleFileCount + pageSize, changes.count)
                    }
            }
        }
        .listStyle(.inset)
        .onChange(of: changes.first?.id) {
            visibleFileCount = pageSize
            revealSelectedFile()
        }
        .onChange(of: selectedFile) {
            revealSelectedFile()
        }
    }

    private func revealSelectedFile() {
        guard let selectedFile,
              let index = changes.firstIndex(where: { $0.id == selectedFile.id }) else { return }
        visibleFileCount = max(visibleFileCount, index + 1)
    }
    
    private func fileName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
    
    private func directory(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().path
    }
    
    private func statusSymbol(for status: CommitFileStatus) -> String {
        switch status {
        case .added: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        case .copied: return "doc.on.doc.fill"
        }
    }
    
    private func statusColor(for status: CommitFileStatus) -> Color {
        switch status {
        case .added: return .green
        case .modified: return .orange
        case .deleted: return .red
        case .renamed: return .blue
        case .copied: return .purple
        }
    }
}
