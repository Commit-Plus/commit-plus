// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// Leaves row dragging with SwiftUI and replaces only the native session image.
@MainActor
final class HistoryDragPreviewDataSource: NSObject, NSTableViewDataSource, NSOutlineViewDataSource {
    weak var original: (any NSTableViewDataSource)?
    var previewImage: NSImage?

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forRowIndexes rowIndexes: IndexSet
    ) {
        original?.tableView?(
            tableView, draggingSession: session,
            willBeginAt: screenPoint, forRowIndexes: rowIndexes
        )
        replacePreview(in: session, tableView: tableView, at: screenPoint)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItems draggedItems: [Any]
    ) {
        // SwiftUI can back Table with an NSOutlineView, which sends this
        // callback instead of the NSTableView row-index callback.
        (original as? any NSOutlineViewDataSource)?.outlineView?(
            outlineView, draggingSession: session,
            willBeginAt: screenPoint, forItems: draggedItems
        )
        replacePreview(in: session, tableView: outlineView, at: screenPoint)
    }

    private func replacePreview(
        in session: NSDraggingSession,
        tableView: NSTableView,
        at screenPoint: NSPoint
    ) {
        guard let image = previewImage else { return }
        previewImage = nil
        session.draggingFormation = .none
        let point = tableView.convert(tableView.window?.convertPoint(fromScreen: screenPoint) ?? .zero, from: nil)
        session.enumerateDraggingItems(
            options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]
        ) { item, index, _ in
            // The payload already contains the full commit selection. Show one
            // preview with its count badge rather than overlapping row images.
            if index == 0 {
                item.setDraggingFrame(
                    NSRect(x: point.x - image.size.width / 2,
                           y: point.y - image.size.height / 2,
                           width: image.size.width, height: image.size.height),
                    contents: image
                )
            } else {
                item.imageComponentsProvider = { [] }
            }
        }
    }

    func prepare(_ presentation: CommitDragPreviewPresentation, in tableView: NSTableView) {
        let content = CommitDragPreview(presentation: presentation, onDragStateChange: { _ in })
            .environment(\.colorScheme, tableView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = tableView.window?.backingScaleFactor ?? 2
        previewImage = renderer.nsImage
    }
}
