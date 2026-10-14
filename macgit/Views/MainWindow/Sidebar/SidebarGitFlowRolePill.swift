// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

final class SidebarGitFlowRolePill: NSView {
    private let label = NSTextField(labelWithString: "")
    private var role: GitFlowBranchRole?
    private var scale: CGFloat = 1

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(label)
        label.alignment = .center
        label.lineBreakMode = .byClipping
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(role: GitFlowBranchRole?, mode: GitFlowRoleDisplayMode, scale: CGFloat) {
        self.role = role
        self.scale = scale
        isHidden = role == nil || mode == .hidden
        let name = role?.rawValue ?? ""
        label.stringValue = mode == .initial ? String(name.prefix(1)) : name
        toolTip = name
        label.font = .systemFont(ofSize: 9 * scale, weight: .semibold)
        label.textColor = color
        setAccessibilityLabel(role?.rawValue ?? "")
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(label.intrinsicContentSize.width) + 12 * scale, height: 17 * scale)
    }

    override func layout() {
        super.layout()
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: 6 * scale, y: (bounds.height - height) / 2,
                             width: max(0, bounds.width - 12 * scale), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        label.textColor = color
        needsDisplay = true
    }

    private var color: NSColor {
        switch role {
        case .main: .systemBlue
        case .develop: .systemYellow
        case .feature: .systemPurple
        case .bugfix: .systemOrange
        case .hotfix: .systemRed
        case .release: .systemGreen
        case nil: .secondaryLabelColor
        }
    }
}
