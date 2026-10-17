// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CoreText
import SwiftUI

/// AppKit-backed conflict pane. Scrolling stays inside NSScrollView and the
/// canvas draws only visible rows, matching DiffNativeTable's rendering model.
struct ConflictCodeNativeView: NSViewRepresentable {
    let rows: [ConflictCodeLine]
    let fileExtension: String
    let highlightColor: NSColor
    let minimumCodeWidth: CGFloat
    let selectionSide: ConflictPaneSelectionSide
    let isSelected: (Int) -> Bool
    let onSelectionChanged: (Int, Bool) -> Void
    let onResolveConflict: (Int, ConflictSectionResolution) -> Void
    let onResolveAll: (ConflictSectionResolution) -> Void
    let scrollID: String
    let scrollController: SyncedScrollController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = context.coordinator.canvas
        context.coordinator.register(
            scrollView: scrollView,
            controller: scrollController,
            id: scrollID
        )
        context.coordinator.apply(self, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.register(
            scrollView: scrollView,
            controller: scrollController,
            id: scrollID
        )
        context.coordinator.apply(self, scrollView: scrollView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.unregister(scrollView: scrollView)
    }

    @MainActor
    final class Coordinator {
        fileprivate let canvas = ConflictCodeCanvas()
        private weak var registeredController: SyncedScrollController?
        private var registeredID: String?

        init() {
            canvas.textStore.onReady = { [weak canvas] _ in
                guard let canvas else { return }
                canvas.setNeedsDisplay(canvas.visibleRect)
            }
        }

        func register(
            scrollView: NSScrollView,
            controller: SyncedScrollController,
            id: String
        ) {
            if registeredController !== controller || registeredID != id {
                unregister(scrollView: scrollView)
            }
            controller.register(scrollView, id: id)
            registeredController = controller
            registeredID = id
        }

        func unregister(scrollView: NSScrollView) {
            guard let registeredController, let registeredID else { return }
            registeredController.unregister(id: registeredID, scrollView: scrollView)
            self.registeredController = nil
            self.registeredID = nil
            canvas.textStore.cancel()
        }

        func apply(_ model: ConflictCodeNativeView, scrollView: NSScrollView) {
            canvas.apply(model)
            let size = CGSize(
                width: max(scrollView.contentSize.width, model.minimumCodeWidth),
                height: max(
                    scrollView.contentSize.height,
                    CGFloat(model.rows.count) * ConflictCodeView.rowHeight()
                        + ConflictCodeView.verticalPadding * 2
                )
            )
            if canvas.frame.size != size {
                canvas.setFrameSize(size)
            }
        }
    }
}

@MainActor
private final class ConflictCodeCanvas: NSView {
    let textStore = DiffNativeTextStore()
    private var rows: [ConflictCodeLine] = []
    private var drawableLines: [DiffLine] = []
    private var fileExtension = ""
    private var highlightColor = NSColor.systemBlue
    private var selectionSide: ConflictPaneSelectionSide = .current
    private var isSelected: (Int) -> Bool = { _ in false }
    private var onSelectionChanged: (Int, Bool) -> Void = { _, _ in }
    private var onResolveConflict: (Int, ConflictSectionResolution) -> Void = { _, _ in }
    private var onResolveAll: (ConflictSectionResolution) -> Void = { _ in }

    private let rowHeight = ConflictCodeView.rowHeight()
    private let verticalPadding = ConflictCodeView.verticalPadding
    private let selectionWidth: CGFloat = 28
    private let lineNumberWidth: CGFloat = 48
    private var textOriginX: CGFloat { selectionWidth + lineNumberWidth + 8 }

    override var isFlipped: Bool { true }

    func apply(_ model: ConflictCodeNativeView) {
        let contentChanged = rows != model.rows
        let syntaxChanged = fileExtension != model.fileExtension
        rows = model.rows
        fileExtension = model.fileExtension
        highlightColor = model.highlightColor
        selectionSide = model.selectionSide
        isSelected = model.isSelected
        onSelectionChanged = model.onSelectionChanged
        onResolveConflict = model.onResolveConflict
        onResolveAll = model.onResolveAll

        if contentChanged {
            drawableLines = model.rows.map {
                DiffLine(oldLineNumber: nil, newLineNumber: $0.lineNumber, text: $0.text, type: .context)
            }
        }
        if contentChanged || syntaxChanged {
            textStore.reset(
                fontName: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName,
                fontSize: 12,
                addedTextColor: .textColor,
                removedTextColor: .textColor,
                fileExtension: model.fileExtension,
                syntaxHighlighting: true
            )
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let visible = dirtyRect.intersection(bounds)
        guard !visible.isNull,
              !visible.isInfinite,
              visible.minY.isFinite,
              visible.maxY.isFinite,
              visible.width > 0,
              visible.height > 0 else {
            return
        }

        NSColor.textBackgroundColor.setFill()
        visible.fill()

        let lower = max(0, Int(floor((visible.minY - verticalPadding) / rowHeight)))
        let upper = min(
            rows.count,
            Int(ceil((visible.maxY - verticalPadding) / rowHeight)) + 1
        )
        guard lower < upper else { return }

        for index in lower..<upper {
            drawRow(index, context: context)
        }
        drawConflictBorders(in: lower..<upper)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x < selectionWidth,
              let index = rowIndex(at: point),
              let sectionIndex = rows[index].conflictSectionIndex,
              rows[index].startsConflict else {
            super.mouseDown(with: event)
            return
        }
        let selected = isSelected(sectionIndex)
        onSelectionChanged(sectionIndex, !selected)
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = rowIndex(at: point) else { return nil }
        let row = rows[index]
        let menu = NSMenu()
        if !row.isPlaceholder {
            menu.addItem(withTitle: "Copy line", action: #selector(copyLine(_:)), keyEquivalent: "")
            menu.items.last?.representedObject = row.text
            menu.items.last?.target = self
            menu.addItem(.separator())
        }
        if row.isConflict, let sectionIndex = row.conflictSectionIndex {
            addResolveItem("Take Incoming", resolution: .incoming, sectionIndex: sectionIndex, to: menu)
            addResolveItem("Take Current", resolution: .current, sectionIndex: sectionIndex, to: menu)
            menu.addItem(.separator())
            addResolveItem("Take Both (Incoming First)", resolution: .bothIncomingFirst, sectionIndex: sectionIndex, to: menu)
            addResolveItem("Take Both (Current First)", resolution: .both, sectionIndex: sectionIndex, to: menu)
        } else {
            addResolveAllItem("Take All Incoming", resolution: .incoming, to: menu)
            addResolveAllItem("Take All Current", resolution: .current, to: menu)
        }
        return menu
    }

    @objc private func copyLine(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func resolve(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ConflictResolveMenuAction else { return }
        onResolveConflict(action.sectionIndex, action.resolution)
    }

    @objc private func resolveAll(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let resolution = ConflictSectionResolution(rawValue: rawValue) else { return }
        onResolveAll(resolution)
    }

    private func addResolveItem(
        _ title: String,
        resolution: ConflictSectionResolution,
        sectionIndex: Int,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(resolve(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ConflictResolveMenuAction(
            sectionIndex: sectionIndex,
            resolution: resolution
        )
        menu.addItem(item)
    }

    private func addResolveAllItem(
        _ title: String,
        resolution: ConflictSectionResolution,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(resolveAll(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = resolution.rawValue
        menu.addItem(item)
    }

    private func rowIndex(at point: CGPoint) -> Int? {
        let index = Int(floor((point.y - verticalPadding) / rowHeight))
        return rows.indices.contains(index) ? index : nil
    }

    private func drawRow(_ index: Int, context: CGContext) {
        let row = rows[index]
        let y = verticalPadding + CGFloat(index) * rowHeight
        let rect = CGRect(x: 0, y: y, width: bounds.width, height: rowHeight)

        if row.isPlaceholder {
            NSColor.separatorColor.withAlphaComponent(0.08).setFill()
            rect.fill()
        } else if row.isConflict {
            highlightColor.withAlphaComponent(0.2).setFill()
            rect.fill()
        }

        NSColor.controlBackgroundColor.withAlphaComponent(0.3).setFill()
        CGRect(x: 0, y: y, width: selectionWidth + lineNumberWidth, height: rowHeight).fill()

        if row.startsConflict, let sectionIndex = row.conflictSectionIndex {
            drawCheckbox(selected: isSelected(sectionIndex), y: y)
        }
        if let number = row.lineNumber {
            drawLineNumber(number, y: y)
        }
        guard !row.isPlaceholder else { return }

        let line = drawableLines[index]
        textStore.request(line)
        if DiffLongLineLayout.isLong(line.text) {
            drawLongLine(line, y: y, context: context)
        } else {
            draw(textStore.textLine(for: line), at: CGPoint(x: textOriginX, y: y), context: context)
        }
    }

    private func drawLongLine(_ line: DiffLine, y: CGFloat, context: CGContext) {
        guard let layout = textStore.longLayout(for: line) else {
            let placeholder = NSAttributedString(
                string: "Preparing long line…",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            placeholder.draw(at: CGPoint(x: textOriginX, y: y + 1))
            return
        }
        let viewport = visibleRect.offsetBy(dx: -textOriginX, dy: 0)
        for chunkIndex in layout.visibleChunks(in: viewport) {
            let chunk = layout.chunks[chunkIndex]
            let text = textStore.textLine(
                for: line,
                chunk: chunkIndex,
                text: String(layout.text[chunk.range])
            )
            draw(text, at: CGPoint(x: textOriginX + chunk.offset, y: y), context: context)
        }
    }

    private func draw(_ line: CTLine, at point: CGPoint, context: CGContext) {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        context.saveGState()
        context.translateBy(x: point.x, y: point.y + (rowHeight - ascent - descent) / 2 + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawLineNumber(_ number: Int, y: CGFloat) {
        let text = NSAttributedString(
            string: String(number),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        let size = text.size()
        text.draw(at: CGPoint(
            x: selectionWidth + lineNumberWidth - size.width - 8,
            y: y + (rowHeight - size.height) / 2
        ))
    }

    private func drawCheckbox(selected: Bool, y: CGFloat) {
        let symbol = NSImage(
            systemSymbolName: selected ? "checkmark.square.fill" : "square",
            accessibilityDescription: nil
        )
        symbol?.isTemplate = true
        (selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).set()
        symbol?.draw(in: CGRect(x: 7, y: y + 2, width: 14, height: 14))
    }

    private func drawConflictBorders(in visibleRows: Range<Int>) {
        var index = visibleRows.lowerBound
        while index < visibleRows.upperBound {
            guard rows[index].isConflict else { index += 1; continue }
            let section = rows[index].conflictSectionIndex
            var start = index
            while start > 0, rows[start - 1].isConflict,
                  rows[start - 1].conflictSectionIndex == section {
                start -= 1
            }
            var end = index + 1
            while end < rows.count, rows[end].isConflict,
                  rows[end].conflictSectionIndex == section {
                end += 1
            }
            highlightColor.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: CGRect(
                x: 0.5,
                y: verticalPadding + CGFloat(start) * rowHeight + 0.5,
                width: max(0, bounds.width - 1),
                height: CGFloat(end - start) * rowHeight - 1
            ))
            border.lineWidth = 1
            border.stroke()
            index = end
        }
    }
}

private final class ConflictResolveMenuAction: NSObject {
    let sectionIndex: Int
    let resolution: ConflictSectionResolution

    init(sectionIndex: Int, resolution: ConflictSectionResolution) {
        self.sectionIndex = sectionIndex
        self.resolution = resolution
    }
}
