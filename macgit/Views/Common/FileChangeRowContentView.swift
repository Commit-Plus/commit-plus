// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Symbol and color used for a file's change type in native file lists.
struct FileChangeStatusStyle {
    let symbol: String
    let color: NSColor
    let label: String
}

extension FileStatus {
    var changeStyle: FileChangeStatusStyle {
        switch self {
        case .added: .init(symbol: "plus.circle.fill", color: .systemGreen, label: "Added")
        case .modified: .init(symbol: "pencil.circle.fill", color: .systemOrange, label: "Modified")
        case .staged: .init(symbol: "pencil.circle.fill", color: .systemOrange, label: "Staged")
        case .deleted: .init(symbol: "minus.circle.fill", color: .systemRed, label: "Deleted")
        case .renamed: .init(symbol: "arrow.right.circle.fill", color: .systemBlue, label: "Renamed")
        case .untracked: .init(symbol: "questionmark.circle.fill", color: .systemGray, label: "Untracked")
        case .conflict: .init(symbol: "exclamationmark.triangle.fill", color: .systemPurple, label: "Conflict")
        }
    }
}

extension CommitFileStatus {
    var changeStyle: FileChangeStatusStyle {
        switch self {
        case .added: .init(symbol: "plus.circle.fill", color: .systemGreen, label: displayText)
        case .modified: .init(symbol: "pencil.circle.fill", color: .systemOrange, label: displayText)
        case .deleted: .init(symbol: "minus.circle.fill", color: .systemRed, label: displayText)
        case .renamed: .init(symbol: "arrow.right.circle.fill", color: .systemBlue, label: displayText)
        case .copied: .init(symbol: "doc.on.doc.fill", color: .systemPurple, label: displayText)
        }
    }
}

/// Shared content of a file row in the File Status, commit detail and pull
/// request file lists: icons, name, optional path lines, and line counts.
/// Cells own their leading controls and trailing accessories and give this
/// view the space between them.
final class FileChangeRowContentView: NSView {
    struct Content {
        var path: String
        var name: String
        var isDirectory = false
        var isExpanded = false
        var status: FileChangeStatusStyle?
        /// Second line under the name; nil keeps the row on a single line.
        var subtitle: String?
        var subtitleEmphasized = false
        /// Optional third line, such as the source path of a rename.
        var detail: String?
        var count: FileLineChangeCount?
        var nameFontSize: CGFloat = 12
        var textScale: CGFloat = 1
    }

    private static let iconSize: CGFloat = 16
    private let icon = FileTypeIconView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let addedLabel = NSTextField(labelWithString: "")
    private let removedLabel = NSTextField(labelWithString: "")
    private var addedWidth: CGFloat = 0
    private var removedWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [icon, nameLabel, subtitleLabel, detailLabel, addedLabel, removedLabel] {
            addSubview(view)
        }
        for label in [nameLabel, subtitleLabel, detailLabel] {
            label.lineBreakMode = .byTruncatingMiddle
        }
        for label in [addedLabel, removedLabel] {
            label.lineBreakMode = .byClipping
            label.maximumNumberOfLines = 1
        }
        detailLabel.textColor = .secondaryLabelColor
        addedLabel.textColor = .systemGreen
        removedLabel.textColor = .systemRed
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ content: Content) {
        let scale = content.textScale
        icon.configure(path: content.path, isDirectory: content.isDirectory, isExpanded: content.isExpanded,
                       statusSymbol: content.status?.symbol, statusColor: content.status?.color,
                       statusLabel: content.status?.label)
        nameLabel.stringValue = content.name
        nameLabel.font = .systemFont(ofSize: content.nameFontSize * scale, weight: .medium)
        subtitleLabel.isHidden = content.subtitle == nil
        subtitleLabel.stringValue = content.subtitle ?? ""
        subtitleLabel.font = .systemFont(ofSize: 10 * scale)
        subtitleLabel.textColor = content.subtitleEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
        detailLabel.isHidden = content.detail == nil
        detailLabel.stringValue = content.detail ?? ""
        detailLabel.font = .systemFont(ofSize: 9 * scale)
        if let count = content.count {
            let font = NSFont.monospacedSystemFont(ofSize: 10 * scale, weight: .medium)
            addedLabel.font = font
            removedLabel.font = font
            addedLabel.stringValue = "+\(count.added)"
            removedLabel.stringValue = "−\(count.removed)"
            addedLabel.setAccessibilityLabel("\(count.added) lines added")
            removedLabel.setAccessibilityLabel("\(count.removed) lines removed")
            // AppKit's intrinsic width can end on the final glyph's antialiased edge.
            // Keep a small trailing allowance so the last digit is never clipped.
            addedWidth = ceil(addedLabel.intrinsicContentSize.width) + 3
            removedWidth = ceil(removedLabel.intrinsicContentSize.width) + 3
            addedLabel.isHidden = false
            removedLabel.isHidden = false
        } else {
            addedWidth = 0
            removedWidth = 0
            addedLabel.isHidden = true
            removedLabel.isHidden = true
        }
        // Counts arrive asynchronously and change the manually laid out widths.
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        let size = Self.iconSize
        icon.frame = NSRect(x: 0, y: midY - size / 2, width: icon.width(iconSize: size), height: size)
        let textX = icon.frame.maxX + 5
        let textWidth = max(20, bounds.maxX - textX)
        let countWidth = addedWidth + removedWidth + (addedWidth > 0 ? 4 : 0)
        let countGap: CGFloat = countWidth > 0 ? 6 : 0

        // Stack the visible text lines and center the block vertically.
        let nameHeight: CGFloat = 18, subtitleHeight: CGFloat = 16, detailHeight: CGFloat = 14
        let blockHeight = nameHeight + (subtitleLabel.isHidden ? 0 : subtitleHeight)
            + (detailLabel.isHidden ? 0 : detailHeight)
        let nameY = floor(midY + blockHeight / 2 - nameHeight)
        let countsY: CGFloat
        if subtitleLabel.isHidden {
            nameLabel.frame = NSRect(x: textX, y: nameY, width: max(20, textWidth - countWidth - countGap), height: nameHeight)
            countsY = nameY + 1
        } else {
            nameLabel.frame = NSRect(x: textX, y: nameY, width: textWidth, height: nameHeight)
            countsY = nameY - subtitleHeight
            subtitleLabel.frame = NSRect(x: textX, y: countsY,
                                         width: max(20, textWidth - countWidth - countGap), height: subtitleHeight)
        }
        detailLabel.frame = NSRect(x: textX, y: countsY - detailHeight, width: textWidth, height: detailHeight)
        removedLabel.frame = NSRect(x: bounds.maxX - removedWidth, y: countsY, width: removedWidth, height: 16)
        addedLabel.frame = NSRect(x: removedLabel.frame.minX - 4 - addedWidth, y: countsY, width: addedWidth, height: 16)
    }
}
