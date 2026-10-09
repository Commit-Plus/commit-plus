// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Only the visible vertical slice has a horizontal scroll surface. Even a hunk
/// with a million rows creates just a screenful of hosting views, never a giant
/// hosting view or a nested table with an unbounded viewport.
final class DiffNativeHunkView: DiffFlippedView {
    let header = DiffNativeCell()
    let horizontalScroll = DiffHunkScrollView()
    private let lines = DiffFlippedView()
    private(set) var cells: [Int: DiffNativeCell] = [:]
    var onHorizontalScroll: ((CGRect) -> Void)?
    private var observer: NSObjectProtocol?
    private var sliceStart: CGFloat = 0
    private var sliceHeight: CGFloat = 0
    private var lastViewport = CGRect.zero
    private var updatingGeometry = false
    private var pendingOffset: CGFloat?
    private var rowLayout: CGRect?
    private var rowRange = 0..<0
    private var spareCells: [DiffNativeCell] = []

    var horizontalOffset: CGFloat { pendingOffset ?? max(0, horizontalScroll.contentView.bounds.minX) }
    var horizontalViewport: CGRect {
        let bounds = horizontalScroll.contentView.bounds
        return CGRect(x: floor(max(0, bounds.minX) / 256) * 256, y: 0,
                      width: ceil(max(1, bounds.width) / 256) * 256 + 256, height: 0)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(header)
        addSubview(horizontalScroll)
        horizontalScroll.hasHorizontalScroller = true
        horizontalScroll.hasVerticalScroller = false
        horizontalScroll.verticalScrollElasticity = .none
        horizontalScroll.scrollerStyle = .overlay
        horizontalScroll.autohidesScrollers = true
        horizontalScroll.drawsBackground = false
        horizontalScroll.documentView = lines
        horizontalScroll.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: horizontalScroll.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.updatingGeometry else { return }
                let viewport = self.horizontalViewport
                guard viewport != self.lastViewport else { return }
                self.lastViewport = viewport
                self.onHorizontalScroll?(viewport)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func updateGeometry(visible: CGRect, headerHeight: CGFloat, lineHeight: CGFloat,
                        lineCount: Int, contentWidth: CGFloat, restoredOffset: CGFloat?) {
        updatingGeometry = true
        if let restoredOffset { pendingOffset = restoredOffset }
        let headerFrame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        if header.frame != headerFrame { header.frame = headerFrame }
        let bodyHeight = CGFloat(lineCount) * lineHeight
        // Small hunks move entirely with the outer clip. Cropping their native
        // scroll view each pixel needlessly resizes every hosted row at the edge.
        let wholeBody = bodyHeight <= max(0, visible.height)
        sliceStart = wholeBody ? 0 : min(bodyHeight, max(0, visible.minY - headerHeight))
        let end = wholeBody ? bodyHeight : min(bodyHeight, max(0, visible.maxY - headerHeight))
        sliceHeight = max(0, end - sliceStart)
        horizontalScroll.isHidden = sliceHeight == 0
        let scrollFrame = CGRect(x: 0, y: headerHeight + sliceStart, width: bounds.width, height: sliceHeight)
        if horizontalScroll.frame != scrollFrame { horizontalScroll.frame = scrollFrame }
        let size = CGSize(width: max(bounds.width, contentWidth), height: sliceHeight)
        if lines.frame.size != size { lines.setFrameSize(size) }
        if contentWidth > 0, let pendingOffset {
            let x = min(pendingOffset, max(0, size.width - horizontalScroll.contentView.bounds.width))
            horizontalScroll.contentView.scroll(to: CGPoint(x: x, y: 0))
            horizontalScroll.reflectScrolledClipView(horizontalScroll.contentView)
            self.pendingOffset = nil
        }
        updatingGeometry = false
        let viewport = horizontalViewport
        if viewport != lastViewport {
            lastViewport = viewport
            onHorizontalScroll?(viewport)
        }
    }

    func updateLines(lineCount: Int, lineHeight: CGFloat, refresh: Bool = false,
                     configure: (DiffNativeCell, Int, Bool) -> Void) {
        let visible = DiffHunkGeometry.visibleLines(
            start: sliceStart, height: sliceHeight, lineHeight: lineHeight, count: lineCount)
        let layout = CGRect(x: 0, y: sliceStart, width: lines.bounds.width, height: lineHeight)
        guard refresh || rowLayout != layout || rowRange != visible else { return }
        rowLayout = layout
        rowRange = visible
        for index in Array(cells.keys) where !visible.contains(index) {
            if let cell = cells.removeValue(forKey: index) {
                cell.removeFromSuperview()
                spareCells.append(cell)
            }
        }
        for index in visible {
            let created = cells[index] == nil
            let cell = cells[index] ?? spareCells.popLast() ?? DiffNativeCell()
            if created {
                cells[index] = cell
                lines.addSubview(cell)
            }
            let frame = CGRect(x: 0, y: CGFloat(index) * lineHeight - sliceStart,
                               width: lines.bounds.width, height: lineHeight)
            if cell.frame != frame { cell.frame = frame }
            configure(cell, index, created)
        }
        if spareCells.count > 32 { spareCells.removeFirst(spareCells.count - 32) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()
    }
}
