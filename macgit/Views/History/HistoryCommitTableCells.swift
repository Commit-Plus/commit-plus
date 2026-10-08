// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

func historyCalloutFont(_ scale: CGFloat) -> NSFont {
    let font = NSFont.preferredFont(forTextStyle: .callout)
    return NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scale) ?? font
}

final class HistoryGraphCellView: NSTableCellView {
    private var geometry: CommitGraphRowGeometry?
    private var rowIndex = 0
    override var isFlipped: Bool { true }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { needsDisplay = true } }
    func configure(model: CommitGraphModel?, rowIndex: Int) {
        self.rowIndex = rowIndex
        geometry = model.map { $0.rowGeometryCache.geometry(for: $0, rowIndex: rowIndex) }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let geometry, let context = NSGraphicsContext.current?.cgContext else { return }
        let colors = NSColor.alternatingContentBackgroundColors
        let background = backgroundStyle == .emphasized ? NSColor.selectedContentBackgroundColor : colors[rowIndex % colors.count]
        context.saveGState()
        context.scaleBy(x: 1, y: bounds.height / CommitGraphRowRenderer.rowHeight)
        CommitGraphRowRenderer.draw(geometry, rowIndex: rowIndex, in: context, dotBackground: background)
        context.restoreGState()
    }
}

final class HistoryMessageCellView: NSTableCellView {
    private let badges = (0..<3).map { _ in HistoryRefBadgeView() }
    private let overflow = NSTextField(labelWithString: "")
    private let message = NSTextField(labelWithString: "")
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { badges.forEach { $0.emphasized = backgroundStyle == .emphasized } }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = NSStackView(views: badges.map { $0 as NSView } + [overflow, message])
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        message.lineBreakMode = .byTruncatingTail
        message.maximumNumberOfLines = 1
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        overflow.setContentCompressionResistancePriority(.required, for: .horizontal)
        overflow.textColor = .secondaryLabelColor
        textField = message
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(commit: Commit, colorIndex: Int?, textScale: CGFloat) {
        for (index, badge) in badges.enumerated() {
            badge.isHidden = index >= commit.refs.count
            if !badge.isHidden { badge.configure(text: commit.refs[index], graphColorIndex: colorIndex, textScale: textScale) }
            badge.emphasized = backgroundStyle == .emphasized
        }
        overflow.isHidden = commit.refs.count <= 3
        overflow.stringValue = "+\(max(0, commit.refs.count - 3))"
        overflow.toolTip = commit.refs.dropFirst(3).joined(separator: "\n")
        overflow.font = .systemFont(ofSize: NSFont.smallSystemFontSize * textScale)
        message.stringValue = commit.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<empty message>" : commit.message
        message.font = historyCalloutFont(textScale)
        message.toolTip = message.stringValue
    }
}

final class HistoryTextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("HHmmddMMMyyyy")
        return formatter
    }()
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        textField = label
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(commit: Commit, column: String, textScale: CGFloat) {
        let font = historyCalloutFont(textScale)
        label.font = font
        label.textColor = .secondaryLabelColor
        switch column {
        case "author": label.stringValue = "\(commit.author) <\(commit.email)>"
        case "date":
            label.stringValue = Self.dateFormatter.string(from: commit.date)
            label.font = .monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        default:
            label.stringValue = commit.shortHash
            label.font = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            label.textColor = .tertiaryLabelColor
        }
        label.toolTip = column == "commit" ? commit.hash : label.stringValue
    }
}

final class HistoryLoadingCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "Loading older commits…")
    override init(frame: NSRect) {
        super.init(frame: frame)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [spinner, label])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(textScale: CGFloat) { label.font = historyCalloutFont(textScale) }
}
