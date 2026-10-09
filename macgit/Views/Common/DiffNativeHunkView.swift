// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Only the visible vertical slice has a horizontal scroll surface. Every hunk
/// has one native canvas and one hosted header, independent of its row count.
final class DiffNativeHunkView: DiffFlippedView {
    let header = DiffNativeCell()
    let horizontalScroll = DiffHunkScrollView()
    private let lines = DiffFlippedView()
    let canvas = DiffHunkCanvas()
    private var observer: NSObjectProtocol?
    private var sliceStart: CGFloat = 0
    private var sliceHeight: CGFloat = 0
    private var updatingGeometry = false
    private var pendingOffset: CGFloat?

    var horizontalOffset: CGFloat {
        pendingOffset ?? max(0, horizontalScroll.contentView.bounds.minX)
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
        lines.addSubview(canvas)
        horizontalScroll.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: horizontalScroll.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.updatingGeometry else { return }
                self.updateCanvasViewport()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func updateGeometry(
        visible: CGRect, headerHeight: CGFloat, lineHeight: CGFloat,
        lineCount: Int, contentWidth: CGFloat, restoredOffset: CGFloat?
    ) {
        updatingGeometry = true
        if let restoredOffset { pendingOffset = restoredOffset }
        let headerFrame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        if header.frame != headerFrame { header.frame = headerFrame }
        let bodyHeight = CGFloat(lineCount) * lineHeight
        // Small hunks move entirely with the outer clip. Cropping their native
        // scroll view each pixel needlessly redraws otherwise unchanged content.
        let wholeBody = bodyHeight <= max(0, visible.height)
        sliceStart =
            wholeBody
            ? 0
            : min(
                bodyHeight,
                max(0, floor((visible.minY - headerHeight) / (lineHeight * 16)) * lineHeight * 16))
        let end =
            wholeBody
            ? bodyHeight
            : min(
                bodyHeight,
                max(0, ceil((visible.maxY - headerHeight) / (lineHeight * 16)) * lineHeight * 16))
        sliceHeight = max(0, end - sliceStart)
        horizontalScroll.isHidden = sliceHeight == 0
        let scrollFrame = CGRect(
            x: 0, y: headerHeight + sliceStart, width: bounds.width, height: sliceHeight)
        if horizontalScroll.frame != scrollFrame { horizontalScroll.frame = scrollFrame }
        let size = CGSize(width: max(bounds.width, contentWidth), height: sliceHeight)
        if lines.frame.size != size { lines.setFrameSize(size) }
        if contentWidth > 0, let pendingOffset {
            let x = min(
                pendingOffset, max(0, size.width - horizontalScroll.contentView.bounds.width))
            horizontalScroll.contentView.scroll(to: CGPoint(x: x, y: 0))
            horizontalScroll.reflectScrolledClipView(horizontalScroll.contentView)
            self.pendingOffset = nil
        }
        updatingGeometry = false
        updateCanvasViewport()
    }

    private func updateCanvasViewport() {
        let clip = horizontalScroll.contentView.bounds
        let origin = CGPoint(x: max(0, clip.minX), y: sliceStart)
        let size = CGSize(width: max(0, clip.width), height: sliceHeight)
        // The document retains the full horizontal extent for AppKit scrolling,
        // but its only drawing surface is never wider than the viewport.
        if canvas.frame.origin.x != origin.x {
            canvas.setFrameOrigin(CGPoint(x: origin.x, y: 0))
        }
        canvas.updateViewport(origin: origin, size: size)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()
    }
}
