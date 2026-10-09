// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

final class HistoryRefBadgeView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var style = RefLabelStyle(text: "", graphColorIndex: nil)
    var emphasized = false { didSet { updateColors() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(text: String, graphColorIndex: Int?, textScale: CGFloat) {
        style = RefLabelStyle(text: text, graphColorIndex: graphColorIndex)
        label.stringValue = style.displayText
        label.font = .systemFont(ofSize: 11 * textScale, weight: .semibold)
        icon.image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: style.isTag ? "Tag" : "Branch")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        toolTip = text
        setAccessibilityLabel(text)
        invalidateIntrinsicContentSize()
        updateColors()
    }
    override var intrinsicContentSize: NSSize {
        NSSize(width: label.intrinsicContentSize.width + icon.intrinsicContentSize.width + 15,
               height: label.intrinsicContentSize.height + 2)
    }
    override func layout() { super.layout(); layer?.cornerRadius = bounds.height / 2 }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        let color: NSColor = emphasized ? .labelColor : style.foreground
        label.textColor = color
        icon.contentTintColor = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (emphasized ? NSColor.labelColor.withAlphaComponent(0.12) : style.background).cgColor
        }
    }
}
