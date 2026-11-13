// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RevisionBrowserView: View {
    let controller: RevisionBrowserController
    let actions: RevisionFileActionCenter
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
            RevisionTreeBrowser(controller: controller, autosaveName: "RevisionBrowserDetailSplit",
                                actions: actions, onCompare: onCompare)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The tree and file preview of a repository at one revision. Shared by the
/// revision browser window and the History detail "File Tree" tab.
struct RevisionTreeBrowser: View {
    let controller: RevisionBrowserController
    let autosaveName: String
    var actions: RevisionFileActionCenter? = nil
    /// Delays the initial load so quickly stepping through commits does not load every tree.
    var loadDelay: Duration = .zero
    /// A path to select once the tree has loaded.
    var initialPath: String? = nil
    /// False when the owner keeps the controller loaded across appearances, such as tab switches.
    var releasesOnDisappear = true
    var onOpenFile: ((String) -> Void)? = nil
    var onSelectFile: ((String) -> Void)? = nil
    var onCompare: ((ComparisonPath, String) -> Void)? = nil
    @State private var lfsRemotes: [String] = []
    @State private var lfsRemote = ""
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        Group {
            if controller.isLoading || (controller.snapshot == nil && controller.error == nil) {
                ProgressView("Loading repository…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = controller.error {
                VStack {
                    EmptyStateView(icon: "exclamationmark.triangle", message: "Unable to browse revision", detail: error)
                    Button("Retry") { controller.load() }
                        .pointingHandCursor()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PersistentHSplit(
                    autosaveName: autosaveName,
                    // Explicit limits keep AppKit from re-measuring the tree and file on every scroll update.
                    minimumLeftWidth: 220, minimumRightWidth: 320,
                    left: { tree.frame(maxWidth: .infinity, maxHeight: .infinity) },
                    right: { filePreview.frame(maxWidth: .infinity, maxHeight: .infinity) }
                )
            }
        }
        // Restarts when the requested path changes, so the newest request wins even while loading.
        .task(id: initialPath) {
            if controller.snapshot == nil {
                if loadDelay > .zero {
                    do { try await Task.sleep(for: loadDelay) } catch { return }
                }
                controller.load()
            }
            if let initialPath, controller.selectedEntry?.path != initialPath {
                await controller.reveal(path: initialPath)
            }
        }
        .task {
            lfsRemotes = await GitStatusService.shared.remotes(in: controller.repositoryURL)
            if lfsRemotes.count == 1 { lfsRemote = lfsRemotes[0] }
        }
        .onDisappear { if releasesOnDisappear { controller.releaseResources() } }
    }

    @ViewBuilder private var tree: some View {
        if controller.children[""]?.isEmpty == true {
            Text("This revision contains no files.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RevisionTreeNativeList(rows: treeRows, selectedID: controller.selectedEntry?.id,
                reveal: controller.revealRequest, textScale: textScale,
                onSelect: { entry in
                    controller.select(entry)
                    if !entry.isDirectory { onSelectFile?(entry.path) }
                },
                onToggle: { controller.toggle($0) },
                makeContextMenu: { entry in NSHostingMenu(rootView: treeMenu(for: entry)) })
        }
    }

    private var treeRows: [RevisionTreeNativeList.Row] {
        controller.visibleEntries.map { entry in
            let expanded = controller.expanded.contains(entry.path)
            var note: String?
            if expanded {
                if let error = controller.folderErrors[entry.path] {
                    note = error + " Collapse and expand to retry."
                } else if controller.children[entry.path]?.isEmpty == true {
                    note = "Empty folder"
                }
            }
            return .init(entry: entry, depth: entry.path.split(separator: "/").count - 1, isExpanded: expanded,
                isLoading: controller.loadingFolders.contains(entry.path), note: note)
        }
    }

    @ViewBuilder private func treeMenu(for entry: RevisionTreeEntry) -> some View {
        if let actions, let snapshot = controller.snapshot, !entry.isDirectory, !entry.isSubmodule {
            RevisionFileMenuItems(actions: actions, path: entry.path, revision: snapshot.commitID,
                onOpen: onOpenFile.map { open in { open(entry.path) } })
        } else {
            Button("Copy Path") { copy(entry.path) }
        }
        Button("Copy Object ID") { copy(entry.objectID) }
        if onCompare != nil {
            Button("Compare with Revision…") { compare(entry) }
        }
    }

    @ViewBuilder private var filePreview: some View {
        if let entry = controller.selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    RevisionTreeIcon(entry: entry, isExpanded: false).frame(width: 16, height: 16)
                    Text(entry.path).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    if let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                    Spacer(minLength: 8)
                    Group {
                        Button("Copy Path", systemImage: "doc.on.doc") { copy(entry.path) }
                            .help("Copy path")
                        Button("Copy Contents", systemImage: "doc.on.clipboard") {
                            if let text = controller.preview?.text { copy(text) }
                        }
                        .disabled(controller.preview?.text == nil)
                        .help("Copy file contents")
                        if onCompare != nil {
                            Button("Compare with Revision…", systemImage: "arrow.left.arrow.right") { compare(entry) }
                                .help("Compare with revision…")
                        }
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).pointingHandCursor()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .help("\(entry.path)\n\(entry.objectType) · mode \(entry.mode)\n\(entry.objectID)")
                if controller.preview?.lfsPointer != nil {
                    HStack {
                        Picker("Download remote", selection: $lfsRemote) {
                            Text("Choose remote").tag("")
                            ForEach(lfsRemotes, id: \.self) { Text($0).tag($0) }
                        }
                        GitLFSPreviewDownloadButton(controller: controller, remote: lfsRemote)
                            .id(entry.id)
                    }.padding(12)
                }
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
                    CommitFilePreviewContent(lines: preview.lines, fileExtension: SyntaxHighlighter.syntaxIdentifier(forFilePath: entry.path), embedded: true)
                        .id(entry.id)
                } else {
                    EmptyStateView(icon: "folder", message: "Expand this folder to browse its files")
                }
            }
        } else {
            EmptyStateView(icon: "doc.text.magnifyingglass", message: "Select a file to preview")
        }
    }

    private func compare(_ entry: RevisionTreeEntry) {
        guard let snapshot = controller.snapshot else { return }
        onCompare?(ComparisonPath(path: entry.path, isDirectory: entry.isDirectory), snapshot.commitID)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
