// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RevisionBrowserView: View {
    let controller: RevisionBrowserController
    let onCompare: (ComparisonPath, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.snapshot?.subject ?? "Repository at Revision").font(.headline).lineLimit(2)
                    Text("\(controller.repositoryURL.lastPathComponent) · \((controller.snapshot?.commitID ?? controller.revision).prefix(8)) · Read-only")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("Copy Commit SHA", systemImage: "doc.on.doc") {
                    copy(controller.snapshot?.commitID ?? controller.revision)
                }
                .pointingHandCursor()
                .disabled(controller.snapshot == nil)
            }
            .padding(12)
            Divider()
            if controller.isLoading {
                ProgressView("Loading repository…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = controller.error {
                VStack {
                    EmptyStateView(icon: "exclamationmark.triangle", message: "Unable to browse revision", detail: error)
                    Button("Retry") { controller.load() }
                        .pointingHandCursor()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PersistentHSplit(
                    autosaveName: "RevisionBrowserDetailSplit",
                    left: { tree.frame(minWidth: 220, idealWidth: 300, maxWidth: 500) },
                    right: { filePreview.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity) }
                )
            }
        }
        .task { controller.load() }
    }

    private var tree: some View {
        List {
            if controller.children[""]?.isEmpty == true {
                Text("This revision contains no files.").foregroundStyle(.secondary)
            }
            ForEach(controller.visibleEntries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if entry.isDirectory {
                            Button {
                                controller.toggle(entry)
                            } label: {
                                Image(systemName: controller.expanded.contains(entry.path) ? "chevron.down" : "chevron.right")
                                    .frame(width: 16, height: 22).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .accessibilityLabel("\(controller.expanded.contains(entry.path) ? "Collapse" : "Expand") \(entry.name)")
                        } else {
                            Color.clear.frame(width: 16, height: 1)
                        }
                        Button {
                            controller.select(entry)
                            if entry.isDirectory { controller.toggle(entry) }
                        } label: {
                            HStack {
                                RevisionTreeIcon(entry: entry, isExpanded: controller.expanded.contains(entry.path))
                                Text(entry.name)
                                    .fontWeight(isChanged(entry) ? .semibold : .regular)
                                    .foregroundStyle(isChanged(entry) ? Color.accentColor : Color.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if isChanged(entry) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityLabel(entry.isDirectory ? "Contains changes in this commit" : "Changed in this commit")
                                }
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .accessibilityHint(entry.isDirectory ? "Expand or collapse folder" : "Preview file")
                        if controller.loadingFolders.contains(entry.path) { ProgressView().controlSize(.small) }
                    }
                    .padding(.leading, CGFloat(min(entry.path.split(separator: "/").count - 1, 20)) * 14)
                    if controller.expanded.contains(entry.path) {
                        if let error = controller.folderErrors[entry.path] {
                            Text(error + " Collapse and expand to retry.").font(.caption).foregroundStyle(.secondary)
                        } else if controller.children[entry.path]?.isEmpty == true {
                            Text("Empty folder").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(controller.selectedEntry?.id == entry.id ? Color.accentColor.opacity(0.18) : Color.clear)
                .contextMenu {
                    Button("Copy Path") { copy(entry.path) }
                    Button("Copy Object ID") { copy(entry.objectID) }
                    Button("Compare with Revision…") { compare(entry) }
                }
                .help(entry.path)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var filePreview: some View {
        if let entry = controller.selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.path).font(.headline).textSelection(.enabled)
                    Text("\(entry.objectType) · mode \(entry.mode)\(entry.size.map { " · \($0) bytes" } ?? "")\n\(entry.objectID)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button("Copy Path") { copy(entry.path) }
                            .pointingHandCursor()
                        Button("Copy Contents") { if let text = controller.preview?.text { copy(text) } }
                            .pointingHandCursor()
                            .disabled(controller.preview?.text == nil)
                        Button("Compare with Revision…") { compare(entry) }
                            .pointingHandCursor()
                    }
                }.padding(12)
                Divider()
                if controller.isLoadingPreview {
                    ProgressView("Loading file…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = controller.previewError {
                    EmptyStateView(icon: "exclamationmark.triangle", message: "Unable to read object", detail: error)
                } else if let data = controller.preview?.imageData, let image = NSImage(data: data) {
                    FileImagePreview(image: image)
                        .id(entry.id)
                } else if let message = controller.preview?.message {
                    ScrollView { Text(message).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading) }
                } else if let preview = controller.preview {
                    CommitFilePreviewContent(lines: preview.lines, fileExtension: (entry.path as NSString).pathExtension.lowercased())
                        .id(entry.id)
                } else {
                    EmptyStateView(icon: "folder", message: "Expand this folder to browse its files")
                }
            }
        } else {
            EmptyStateView(icon: "doc.text.magnifyingglass", message: "Select a file to preview")
        }
    }

    private func isChanged(_ entry: RevisionTreeEntry) -> Bool {
        controller.snapshot?.changedNodePaths.contains(entry.path) == true
    }

    private func compare(_ entry: RevisionTreeEntry) {
        guard let snapshot = controller.snapshot else { return }
        onCompare(ComparisonPath(path: entry.path, isDirectory: entry.isDirectory), snapshot.commitID)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
