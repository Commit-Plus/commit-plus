// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct HistoryCommitTable: NSViewRepresentable {
    let listModel: HistoryListModel
    let actions: HistoryCommitActionController
    let customActionStore: CustomActionStore
    let repositoryURL: URL
    let textScale: CGFloat

    func makeCoordinator() -> HistoryCommitTableController { HistoryCommitTableController() }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) {
        let rows = listModel.rows
        let selection = listModel.selection
        let scrollRequest = listModel.scrollRequest
        let dragActive = listModel.dragActiveHashes
        context.coordinator.apply(listModel: listModel, actions: actions, customActionStore: customActionStore,
                                  repositoryURL: repositoryURL, textScale: textScale, rows: rows,
                                  selection: selection, scrollRequest: scrollRequest, dragActive: dragActive)
    }
    static func dismantleNSView(_ view: NSScrollView, coordinator: HistoryCommitTableController) {
        coordinator.removeObservers()
    }
}

final class HistoryNSTableView: NSTableView {
    var dragOriginRow = -1
    var onReturn: (() -> Void)?
    var suppressDoubleClickUntil = Date.distantPast
    private(set) var isHandlingKeyboardSelection = false
    override func mouseDown(with event: NSEvent) {
        dragOriginRow = row(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?() }
        else {
            isHandlingKeyboardSelection = true
            defer { isHandlingKeyboardSelection = false }
            super.keyDown(with: event)
        }
    }
}
