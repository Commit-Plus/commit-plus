// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// AppKit counterpart of `RevisionTreeIcon` for native file lists: a Material
/// file-type icon with an optional status badge in the bottom-trailing corner.
final class FileTypeIconView: NSView {
    private let fileIcon = NSImageView()
    private let badge = NSImageView()
    private var path = ""
    private var isDirectory = false
    private var isExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fileIcon.imageScaling = .scaleProportionallyUpOrDown
        badge.imageScaling = .scaleProportionallyUpOrDown
        badge.wantsLayer = true
        addSubview(fileIcon)
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(path: String, isDirectory: Bool, isExpanded: Bool = false,
                   statusSymbol: String? = nil, statusColor: NSColor? = nil, statusLabel: String? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.isExpanded = isExpanded
        updateFileIcon()
        if let statusSymbol {
            badge.image = NSImage(systemSymbolName: statusSymbol, accessibilityDescription: statusLabel)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
            badge.contentTintColor = statusColor
            badge.isHidden = false
        } else {
            badge.isHidden = true
        }
        setAccessibilityLabel(statusLabel)
        updateBadgeBackground()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        fileIcon.frame = bounds
        let size = round(bounds.width * 0.6)
        badge.frame = NSRect(x: bounds.maxX - size + 2, y: bounds.minY - 2, width: size, height: size)
        badge.layer?.cornerRadius = size / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFileIcon()
        updateBadgeBackground()
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

    private func updateBadgeBackground() {
        // A backing disc keeps the badge legible over the file icon artwork.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            badge.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
    }
}
