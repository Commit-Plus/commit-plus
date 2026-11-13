// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// A single reusable auxiliary window hosting SwiftUI content sized by the window.
@MainActor
final class HostedToolWindowController: NSWindowController, NSWindowDelegate {
    private var onClose: (() -> Void)?

    init() { super.init(window: nil) }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show<Content: View>(title: String, onClose: @escaping () -> Void = {},
                             @ViewBuilder content: () -> Content) {
        close()
        self.onClose = onClose
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: min(1100, visibleFrame.width - 40), height: min(760, visibleFrame.height - 80))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: min(760, size.width), height: min(420, size.height))
        window.delegate = self
        let root = content()
        let hostingView = NSHostingView(rootView: GeometryReader { geometry in
            root.frame(width: geometry.size.width, height: geometry.size.height)
        })
        // Window geometry owns the viewport; content must never expand the window.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: visibleFrame.midX - window.frame.width / 2,
                                      y: visibleFrame.midY - window.frame.height / 2))
        self.window = window
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
        // The hosted content may reference this controller's owner; dropping it breaks that cycle.
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async { closing?.contentView = nil }
    }
}

/// File-level actions for a path at a revision, shared by the commit detail
/// panel and the revision browser: Blame and History windows, Save As, Finder.
@MainActor
final class RevisionFileActionCenter {
    let repositoryURL: URL
    private let blameWindow = HostedToolWindowController()
    private let historyWindow = HostedToolWindowController()

    init(repositoryURL: URL) { self.repositoryURL = repositoryURL }

    func showBlame(path: String, revision: String) {
        let controller = FileBlameController(repositoryURL: repositoryURL, path: path, revision: revision)
        blameWindow.show(title: "Blame — \(path) — \(repositoryURL.lastPathComponent)",
                         onClose: { controller.cancel() }) {
            FileBlameView(controller: controller)
        }
    }

    func showHistory(path: String, revision: String) {
        let controller = FileHistoryController(repositoryURL: repositoryURL, path: path, revision: revision)
        historyWindow.show(title: "History — \(path) — \(repositoryURL.lastPathComponent)",
                           onClose: { controller.cancel() }) {
            FileHistoryView(controller: controller, actions: self)
            // The window holds this content until it closes; `windowWillClose` then releases it.
        }
    }

    func workingCopyExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: repositoryURL.appendingPathComponent(path).path)
    }

    func openWorkingCopy(_ path: String) {
        NSWorkspace.shared.open(repositoryURL.appendingPathComponent(path))
    }

    func showInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(repositoryURL.appendingPathComponent(path).path, inFileViewerRootedAtPath: "")
    }

    func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    /// Writes the file's content at `revision` to a location the user chooses.
    func saveCopy(path: String, revision: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (path as NSString).lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let repositoryURL = repositoryURL
        Task {
            do {
                let data = try await GitStatusService.shared.showFile(at: path, ref: revision, in: repositoryURL)
                try data.write(to: destination, options: .atomic)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not save \((path as NSString).lastPathComponent)"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

/// Context menu items for a file at a revision. Works in SwiftUI context menus and `NSHostingMenu`.
struct RevisionFileMenuItems: View {
    let actions: RevisionFileActionCenter
    let path: String
    let revision: String
    /// False when the file does not exist at `revision` (for example, it was deleted there).
    var existsAtRevision = true
    var onOpen: (() -> Void)? = nil
    var onShowInFileTree: (() -> Void)? = nil

    var body: some View {
        let inWorkingCopy = actions.workingCopyExists(path)
        Button("Open") {
            if let onOpen { onOpen() } else { actions.openWorkingCopy(path) }
        }
        .disabled(!inWorkingCopy)
        Button("Show in Finder") { actions.showInFinder(path) }
            .disabled(!inWorkingCopy)
        Divider()
        Button("Blame…") { actions.showBlame(path: path, revision: revision) }
            .disabled(!existsAtRevision)
        Button("History…") { actions.showHistory(path: path, revision: revision) }
        Divider()
        Button("Save As…") { actions.saveCopy(path: path, revision: revision) }
            .disabled(!existsAtRevision)
        if let onShowInFileTree {
            Button("Show in File Tree", action: onShowInFileTree)
                .disabled(!existsAtRevision)
        }
        Divider()
        Button("Copy Path") { actions.copyPath(path) }
    }
}
