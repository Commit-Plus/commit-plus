// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CoreText

final class SidebarGitFlowRolePill: NSView {
    private var text = ""
    private var font = NSFont.systemFont(ofSize: 9, weight: .semibold)
    private var role: GitFlowBranchRole?
    private var scale: CGFloat = 1

    func configure(role: GitFlowBranchRole?, mode: GitFlowRoleDisplayMode, scale: CGFloat) {
        self.role = role
        self.scale = scale
        isHidden = role == nil || mode == .hidden
        let name = role?.rawValue ?? ""
        text = mode == .initial ? String(name.prefix(1)) : name
        toolTip = name
        font = .systemFont(ofSize: 9 * scale, weight: .semibold)
        setAccessibilityLabel(role?.rawValue ?? "")
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((text as NSString).size(withAttributes: [.font: font]).width) + 12 * scale, height: 17 * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: color]
        ))
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: bounds.midX - glyphBounds.midX,
                                       y: bounds.midY - glyphBounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var color: NSColor {
        switch role {
        case .main: .systemCyan
        case .develop: .systemYellow
        case .feature: .systemPurple
        case .bugfix: .systemOrange
        case .hotfix: .systemRed
        case .release: .systemGreen
        case nil: .secondaryLabelColor
        }
    }
}
