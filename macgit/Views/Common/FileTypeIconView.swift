// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// AppKit counterpart of `RevisionTreeIcon` for native file lists: an optional
/// status icon followed by the Material file-type icon on the same row.
final class FileTypeIconView: NSView {
    static let spacing: CGFloat = 3

    private let statusIcon = NSImageView()
    private let fileIcon = NSImageView()
    private var path = ""
    private var isDirectory = false
    private var isExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        statusIcon.imageScaling = .scaleProportionallyDown
        fileIcon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(statusIcon)
        addSubview(fileIcon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Width needed to show both icons at `iconSize`.
    func width(iconSize: CGFloat) -> CGFloat {
        statusIcon.isHidden ? iconSize : iconSize * 2 + Self.spacing
    }

    func configure(path: String, isDirectory: Bool, isExpanded: Bool = false,
                   statusSymbol: String? = nil, statusColor: NSColor? = nil, statusLabel: String? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.isExpanded = isExpanded
        updateFileIcon()
        if let statusSymbol {
            statusIcon.image = NSImage(systemSymbolName: statusSymbol, accessibilityDescription: statusLabel)
            statusIcon.contentTintColor = statusColor
            statusIcon.isHidden = false
        } else {
            statusIcon.isHidden = true
        }
        setAccessibilityLabel(statusLabel)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = bounds.height
        if statusIcon.isHidden {
            fileIcon.frame = NSRect(x: 0, y: 0, width: size, height: size)
        } else {
            statusIcon.frame = NSRect(x: 0, y: 0, width: size, height: size)
            fileIcon.frame = NSRect(x: size + Self.spacing, y: 0, width: size, height: size)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFileIcon()
    }

    private func updateFileIcon() {
        let isLight = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        if let icons = RevisionMaterialIcons.shared {
            fileIcon.image = NSImage(named: "revision-material-" + icons.icon(
                for: path, isDirectory: isDirectory, isExpanded: isExpanded, isLight: isLight))
            fileIcon.contentTintColor = nil
        } else {
            fileIcon.image = NSImage(systemSymbolName: isDirectory ? "folder" : "doc.text", accessibilityDescription: nil)
            fileIcon.contentTintColor = .secondaryLabelColor
        }
    }
}
