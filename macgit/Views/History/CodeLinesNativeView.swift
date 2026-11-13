// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// Read-only, AppKit-backed listing of a file's lines with line numbers. The
/// table reuses row views and highlights only rows that come into view, so
/// large files scroll smoothly in both directions.
struct CodeLinesNativeView: NSViewRepresentable {
    let lines: [DiffLine]
    let fileExtension: String
    let highlightsSyntax: Bool
    var onVerticalOffsetChange: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.apply(self) }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        private static let cacheLimit = 4_000

        private let scroll = NSScrollView()
        private let table = CodeLinesTableView()
        private let column = NSTableColumn(identifier: .init("code-line"))
        private var model: CodeLinesNativeView?
        private var lines: [DiffLine] = []
        private var highlighter: SyntaxHighlighter?
        private var highlighted: [Int: NSAttributedString] = [:]
        private var contentWidth: CGFloat = 0
        private var lastOffset: CGFloat = .nan
        private var isApplying = false

        func makeScrollView() -> NSScrollView {
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.automaticallyAdjustsContentInsets = false
            column.resizingMask = []
            table.addTableColumn(column)
            table.headerView = nil
            table.backgroundColor = .clear
            table.style = .plain
            table.rowHeight = CommitFilePreviewViewport.rowHeight
            table.intercellSpacing = .zero
            table.columnAutoresizingStyle = .noColumnAutoresizing
            table.allowsMultipleSelection = true
            table.allowsEmptySelection = true
            table.dataSource = self
            table.delegate = self
            table.textProvider = { [weak self] rows in
                guard let self else { return "" }
                return rows.filter { self.lines.indices.contains($0) }.map { self.lines[$0].text }.joined(separator: "\n")
            }
            scroll.documentView = table
            scroll.contentView.postsBoundsChangedNotifications = true
            scroll.contentView.postsFrameChangedNotifications = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            center.addObserver(self, selector: #selector(viewportChanged), name: NSView.frameDidChangeNotification, object: scroll.contentView)
            return scroll
        }

        func stop() {
            NotificationCenter.default.removeObserver(self)
            table.textProvider = nil
            model = nil
        }

        func apply(_ model: CodeLinesNativeView) {
            let previous = self.model
            self.model = model
            isApplying = true
            defer { isApplying = false }
            let sameLines = lines.count == model.lines.count
                && lines.first?.id == model.lines.first?.id && lines.last?.id == model.lines.last?.id
            let sameStyle = previous?.fileExtension == model.fileExtension
                && previous?.highlightsSyntax == model.highlightsSyntax
            guard !sameLines || !sameStyle else { return }
            lines = model.lines
            highlighter = model.highlightsSyntax ? SyntaxHighlighter(fileExtension: model.fileExtension) : nil
            highlighted.removeAll(keepingCapacity: true)
            if !sameLines {
                contentWidth = Self.measureWidth(of: lines)
                updateColumnWidth()
                table.reloadData()
                table.scroll(.zero)
            } else {
                table.reloadData()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { lines.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard lines.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("CodeLineCell")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? CodeLineCell ?? CodeLineCell()
            cell.identifier = id
            cell.configure(number: lines[row].newLineNumber ?? lines[row].oldLineNumber, text: attributedText(row))
            return cell
        }

        private func attributedText(_ row: Int) -> NSAttributedString {
            if let cached = highlighted[row] { return cached }
            let text = lines[row].text
            let result = highlighter?.nsAttributedString(for: text, fontSize: 12)
                ?? NSAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: NSColor.textColor])
            if highlighted.count >= Self.cacheLimit { highlighted.removeAll(keepingCapacity: true) }
            highlighted[row] = result
            return result
        }

        @objc private func viewportChanged() {
            updateColumnWidth()
            let offset = scroll.contentView.bounds.origin.y
            guard offset != lastOffset else { return }
            lastOffset = offset
            guard let report = model?.onVerticalOffsetChange else { return }
            // SwiftUI state must not change while it is updating this view.
            if isApplying { DispatchQueue.main.async { report(offset) } } else { report(offset) }
        }

        private func updateColumnWidth() {
            let width = max(contentWidth, scroll.contentView.bounds.width)
            if abs(column.width - width) > 0.5 { column.width = width }
        }

        /// Measures only the longest lines; the text is monospaced, so they bound the content width.
        private static func measureWidth(of lines: [DiffLine]) -> CGFloat {
            var longest: [(count: Int, index: Int)] = []
            for (index, line) in lines.enumerated() {
                let count = line.text.utf16.count
                if longest.count < 6 {
                    longest.append((count, index))
                } else if let slot = longest.indices.min(by: { longest[$0].count < longest[$1].count }),
                          longest[slot].count < count {
                    longest[slot] = (count, index)
                }
            }
            let width = longest.map { (lines[$0.index].text as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            return ceil(width) + CodeLineCell.textInset + 24
        }
    }
}

private final class CodeLinesTableView: NSTableView {
    var textProvider: ((IndexSet) -> String)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        if !selectedRowIndexes.contains(index) {
            selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        let menu = NSMenu()
        menu.addItem(withTitle: selectedRowIndexes.count > 1 ? "Copy Lines" : "Copy Line", action: #selector(copy(_:)), keyEquivalent: "")
        return menu
    }

    @objc func copy(_ sender: Any?) {
        guard !selectedRowIndexes.isEmpty, let text = textProvider?(selectedRowIndexes) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return !selectedRowIndexes.isEmpty }
        return super.validateUserInterfaceItem(item)
    }
}

private final class CodeLineCell: NSTableCellView {
    static let numberWidth: CGFloat = 44
    static let textInset: CGFloat = 54

    private let number = NSTextField(labelWithString: "")
    private let text = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        number.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        number.textColor = .tertiaryLabelColor
        number.alignment = .right
        text.lineBreakMode = .byClipping
        text.maximumNumberOfLines = 1
        text.cell?.usesSingleLineMode = true
        text.allowsDefaultTighteningForTruncation = false
        addSubview(number)
        addSubview(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(number value: Int?, text attributed: NSAttributedString) {
        number.stringValue = value.map(String.init) ?? ""
        text.attributedStringValue = attributed
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let numberHeight = number.intrinsicContentSize.height
        number.frame = NSRect(x: 0, y: bounds.midY - numberHeight / 2, width: Self.numberWidth, height: numberHeight)
        let textHeight = text.intrinsicContentSize.height
        text.frame = NSRect(x: Self.textInset, y: bounds.midY - textHeight / 2,
                            width: max(0, bounds.width - Self.textInset), height: textHeight)
    }
}
