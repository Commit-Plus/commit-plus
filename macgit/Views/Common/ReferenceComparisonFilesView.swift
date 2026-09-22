// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ReferenceComparisonFilesView: View {
    let controller: ReferenceComparisonController
    @AppStorage("referenceDiff.fileListWidth") private var fileListWidth: Double = 240

    var body: some View {
        if controller.files.isEmpty {
            EmptyStateView(icon: "checkmark.circle", message: "No file changes",
                detail: controller.path != nil ? "No changes for this path between the selected sides." : controller.mode == .mergeBase
                    ? "Target has no file changes since the merge base. Commit histories may still differ."
                    : "These references point to the same tree. Commit histories may still differ.")
        } else if controller.path?.isDirectory == false {
            fileDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                let availableWidth = max(0, geometry.size.width - 6)
                let width = min(CGFloat(fileListWidth), max(180, availableWidth - 300))
                HStack(spacing: 0) {
                    CommitFileListView(changes: controller.files, selectedFile: Binding(
                        get: { controller.selectedFile }, set: controller.selectFile))
                        .frame(width: width)
                    ColumnResizer(
                        leftWidth: Binding(get: { width }, set: { fileListWidth = Double($0) }),
                        rightWidth: Binding(get: { max(40, availableWidth - width) },
                            set: { fileListWidth = Double(availableWidth - $0) }), minimumLeftWidth: 180)
                    fileDetail
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder private var fileDetail: some View {
        if let file = controller.selectedFile {
            VStack(spacing: 0) {
                Text(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                Divider()
                if controller.isLoadingPatch {
                    ProgressView("Loading file diff…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = controller.fileError {
                    EmptyStateView(icon: "exclamationmark.triangle", message: "Could not load file diff", detail: error)
                    Button("Retry") { controller.selectFile(file) }.padding()
                } else if let patch = controller.patch {
                    if patch.isTruncated {
                        Label("Large diff: showing the first 2 MB of output.", systemImage: "exclamationmark.triangle")
                            .font(.caption).padding(8)
                    }
                    if patch.isBinary {
                        EmptyStateView(icon: "doc", message: "Binary file changed", detail: "A text diff is not available for this file.")
                    } else if patch.hunks.isEmpty {
                        EmptyStateView(icon: "doc", message: "No text changes",
                            detail: file.status == .renamed ? "The file was renamed without text changes." : "The change affects file metadata or an empty file.")
                    } else {
                        DiffView(hunks: patch.hunks, repositoryURL: controller.repositoryURL, filePath: file.path)
                    }
                }
            }
        } else {
            EmptyStateView(icon: "doc.text", message: "Select a file", detail: "Click a file to see its changes.")
        }
    }
}
