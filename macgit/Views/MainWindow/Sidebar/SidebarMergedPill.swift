// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CoreText

final class SidebarMergedPill: NSView {
    private let text = "Merged"
    private var font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private var scale: CGFloat = 1
    private var configured = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("Merged")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(visible: Bool, scale: CGFloat) {
        guard !configured || isHidden != !visible || self.scale != scale else { return }
        configured = true
        isHidden = !visible
        self.scale = scale
        font = .systemFont(ofSize: 10 * scale, weight: .semibold)
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(textWidth) + 14 * scale, height: 19 * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor.systemPurple
        color.withAlphaComponent(0.15).setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: bounds.height / 2,
            yRadius: bounds.height / 2
        ).fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        ))
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: bounds.midX - glyphBounds.midX,
            y: bounds.midY - glyphBounds.midY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
