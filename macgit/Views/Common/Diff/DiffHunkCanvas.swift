// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CoreText

/// One viewport-sized drawing surface replaces the hosting tree for every row.
/// Text, gutters and selection are drawn together; menus are built only on demand.
final class DiffHunkCanvas: DiffFlippedView {
    private var hunk: DiffHunk?
    private var textStore: DiffNativeTextStore?
    private var storeGeneration = -1
    private var selectedLineIDs: Set<UUID> = []
    private(set) var lineHeight: CGFloat = 22
    private(set) var contentOrigin = CGPoint.zero
    var onLineTap: ((Int, NSEvent.ModifierFlags) -> Void)?
    var lineMenu: ((Int) -> NSMenu?)?

    func configure(
        hunk: DiffHunk, textStore: DiffNativeTextStore,
        selectedLineIDs: Set<UUID>, lineHeight: CGFloat
    ) {
        let changed =
            self.hunk?.id != hunk.id || self.hunk?.contentRevision != hunk.contentRevision
            || storeGeneration != textStore.generation || self.lineHeight != lineHeight
        let selectionChanges = self.selectedLineIDs.symmetricDifference(selectedLineIDs)
        self.hunk = hunk
        self.textStore = textStore
        self.storeGeneration = textStore.generation
        self.selectedLineIDs = selectedLineIDs
        self.lineHeight = lineHeight
        if changed { needsDisplay = true } else { invalidateLines(selectionChanges) }
        prepareVisibleLines()
    }

    func updateViewport(origin: CGPoint, size: CGSize) {
        guard contentOrigin != origin || frame.size != size else { return }
        contentOrigin = origin
        setFrameSize(size)
        needsDisplay = true
        prepareVisibleLines()
    }

    func cancelPendingWork() {
        // The bounded, shared store owns preparation. A recycled panel releases
        // its hunk so late results cannot redraw content belonging to its old file.
        hunk = nil
        textStore = nil
    }

    private func rows(in rect: CGRect) -> Range<Int> {
        DiffHunkGeometry.visibleLines(
            start: contentOrigin.y + rect.minY,
            height: rect.height, lineHeight: lineHeight,
            count: hunk?.lines.count ?? 0)
    }

    private func prepareVisibleLines() {
        guard let hunk, let textStore else { return }
        for index in rows(in: bounds) { textStore.request(hunk.lines[index]) }
    }

    func invalidateLines(_ ids: Set<UUID>) {
        guard let hunk, !ids.isEmpty else { return }
        for index in rows(in: bounds) where ids.contains(hunk.lines[index].id) {
            setNeedsDisplay(
                CGRect(
                    x: 0, y: CGFloat(index) * lineHeight - contentOrigin.y,
                    width: bounds.width, height: lineHeight))
        }
    }

    func lineIndex(at point: CGPoint) -> Int? {
        guard bounds.contains(point), let hunk, lineHeight > 0 else { return nil }
        let index = Int(floor((point.y + contentOrigin.y) / lineHeight))
        return hunk.lines.indices.contains(index) ? index : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = lineIndex(at: convert(event.locationInWindow, from: nil)) else { return }
        onLineTap?(index, event.modifierFlags)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = lineIndex(at: convert(event.locationInWindow, from: nil)) else {
            return nil
        }
        return lineMenu?(index)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let hunk, let textStore, let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        #if DEBUG
            DiffRenderStats.canvasDraws += 1
        #endif
        DiffSignpost.interval("CanvasDraw") {
            for index in rows(in: dirtyRect.intersection(bounds)) {
                let line = hunk.lines[index]
                let y = CGFloat(index) * lineHeight - contentOrigin.y
                let row = CGRect(x: 0, y: y, width: bounds.width, height: lineHeight)
                guard needsToDraw(row) else { continue }
                background(for: line).setFill()
                row.fill()
                let x = 8 - contentOrigin.x
                drawNumber(line.oldLineNumber, at: CGPoint(x: x, y: y), scale: lineHeight / 22)
                drawNumber(line.newLineNumber, at: CGPoint(x: x + 42, y: y), scale: lineHeight / 22)
                let prefix = prefix(for: line.type)
                let prefixText = NSAttributedString(
                    string: prefix,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(
                            ofSize: 11 * lineHeight / 22, weight: .semibold),
                        .foregroundColor: prefixColor(for: line.type).withAlphaComponent(0.7),
                    ])
                let prefixWidth = prefix.isEmpty ? 0.0 : 14.0
                prefixText.draw(
                    at: CGPoint(
                        x: x + 84 + (prefixWidth - prefixText.size().width) / 2,
                        y: y + (lineHeight - prefixText.size().height) / 2))
                let textX = x + 84 + prefixWidth
                if DiffLongLineLayout.isLong(line.text) {
                    if let layout = textStore.longLayout(for: line) {
                        let viewport = CGRect(
                            x: -textX, y: 0, width: bounds.width, height: lineHeight)
                        for chunkIndex in layout.visibleChunks(in: viewport) {
                            let chunk = layout.chunks[chunkIndex]
                            let text = textStore.textLine(
                                for: line, chunk: chunkIndex,
                                text: String(layout.text[chunk.range]))
                            draw(text, at: CGPoint(x: textX + chunk.offset, y: y), in: context)
                        }
                    } else {
                        let placeholder = NSAttributedString(
                            string: "Preparing long line…",
                            attributes: [
                                .font: NSFont.monospacedSystemFont(
                                    ofSize: textStore.fontSize, weight: .regular),
                                .foregroundColor: NSColor.secondaryLabelColor,
                            ])
                        placeholder.draw(
                            at: CGPoint(
                                x: textX, y: y + (lineHeight - placeholder.size().height) / 2))
                    }
                } else {
                    textStore.request(line)
                    draw(textStore.textLine(for: line), at: CGPoint(x: textX, y: y), in: context)
                }
            }
        }
    }

    private func draw(_ text: CTLine, at point: CGPoint, in context: CGContext) {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        CTLineGetTypographicBounds(text, &ascent, &descent, nil)
        context.saveGState()
        context.translateBy(x: point.x, y: point.y + (lineHeight - ascent - descent) / 2 + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(text, context)
        context.restoreGState()
    }

    private func drawNumber(_ number: Int?, at point: CGPoint, scale: CGFloat) {
        guard let number else { return }
        let text = NSAttributedString(
            string: String(number),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10 * scale, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])
        let size = text.size()
        text.draw(
            at: CGPoint(x: point.x + 36 - size.width, y: point.y + (lineHeight - size.height) / 2))
    }

    private func background(for line: DiffLine) -> NSColor {
        if selectedLineIDs.contains(line.id) { return .controlAccentColor.withAlphaComponent(0.12) }
        switch line.type {
        case .added: return .systemGreen.withAlphaComponent(0.08)
        case .removed: return .systemRed.withAlphaComponent(0.08)
        case .conflictMarker: return .systemPurple.withAlphaComponent(0.10)
        case .context, .header: return .clear
        }
    }

    private func prefix(for type: DiffLineType) -> String {
        switch type {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        case .header: ""
        case .conflictMarker: "!"
        }
    }

    private func prefixColor(for type: DiffLineType) -> NSColor {
        switch type {
        case .added: NSColor(calibratedRed: 0.12, green: 0.55, blue: 0.18, alpha: 1)
        case .removed: NSColor(calibratedRed: 0.75, green: 0.18, blue: 0.18, alpha: 1)
        case .conflictMarker: .systemPurple
        case .header: .secondaryLabelColor
        case .context: .textColor
        }
    }

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        guard let hunk else { return [] }
        return rows(in: visibleRect).map { index in
            let line = hunk.lines[index]
            let row = CGRect(
                x: 0, y: CGFloat(index) * lineHeight - contentOrigin.y,
                width: bounds.width, height: lineHeight
            ).intersection(visibleRect)
            let label =
                "\(line.type) line \(line.newLineNumber ?? line.oldLineNumber ?? 0): \(line.text.prefix(200))"
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityFrame(window?.convertToScreen(convert(row, to: nil)) ?? .zero)
            element.setAccessibilityLabel(label)
            element.setAccessibilityParent(self)
            if (line.oldLineNumber == nil) != (line.newLineNumber == nil) {
                element.setAccessibilityCustomActions([
                    NSAccessibilityCustomAction(name: "Select line") { [weak self] in
                        self?.onLineTap?(index, [])
                        return true
                    }
                ])
            }
            return element
        }
    }
}
