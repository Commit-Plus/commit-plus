//
//  CommitPatchConflictWindowController.swift
//  macgit
//
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software; you can redistribute it and/or modify
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

@MainActor
final class CommitPatchConflictWindowController: NSWindowController, NSWindowDelegate {
    private weak var controller: CommitPatchController?

    init() { super.init(window: nil) }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(file: CommitPatchReviewFile, controller: CommitPatchController) {
        self.controller = controller
        let visibleFrame = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: min(1100, visibleFrame.width - 40),
                          height: min(760, visibleFrame.height - 80))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(file.reviewTitle) — \(file.file.path)"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: min(700, size.width), height: min(500, size.height))
        window.delegate = self
        let hostingView = NSHostingView(rootView: GeometryReader { geometry in
            CommitPatchConflictWindowContent(file: file, controller: controller)
                .frame(width: geometry.size.width, height: geometry.size.height)
        })
        // The window owns the viewport, including for long lines and large diffs.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: visibleFrame.midX - window.frame.width / 2,
                                      y: visibleFrame.midY - window.frame.height / 2))
        self.window = window
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        controller?.isBusy != true
    }

    func windowWillClose(_ notification: Notification) {
        // Release the hosted observation/callbacks before notifying the owner.
        window?.contentView = nil
        window = nil
        let owner = controller
        controller = nil
        owner?.closeConflict()
    }
}

private struct CommitPatchConflictWindowContent: View {
    let file: CommitPatchReviewFile
    let controller: CommitPatchController

    var body: some View {
        CommitPatchConflictSheet(file: file, isBusy: controller.isBusy, errorMessage: controller.reviewError,
            onCancel: { controller.closeConflict() },
            onSkip: { controller.skip(fileID: file.id) },
            onResolve: { result in controller.resolveAndClose(fileID: file.id, result: result) })
    }
}
