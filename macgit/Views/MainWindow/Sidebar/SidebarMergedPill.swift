// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

final class SidebarMergedPill: NSView {
    var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateColors()
        }
    }
    private let label = NSTextField(labelWithString: "Merged")
    private var font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private var scale: CGFloat = 1
    private var configured = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.alignment = .center
        label.font = font
        addSubview(label)
        updateColors()
        setAccessibilityLabel("Merged")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(visible: Bool, scale: CGFloat) {
        guard !configured || isHidden != !visible || self.scale != scale else { return }
        configured = true
        isHidden = !visible
        self.scale = scale
        font = .systemFont(ofSize: 10 * scale, weight: .semibold)
        label.font = font
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = (label.stringValue as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(textWidth) + 14 * scale, height: 19 * scale)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = bounds.height / 2
        CATransaction.commit()
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: 0, y: floor((bounds.height - height) / 2),
                             width: bounds.width, height: height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        // Keep the capsule in its backing layer instead of repainting a
        // transparent CoreText drawing whenever the window becomes active.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            label.textColor = isHighlighted ? .white : .systemPurple
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.15).cgColor
            CATransaction.commit()
        }
    }
}
