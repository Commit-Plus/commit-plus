//
//  ConflictCodeView.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import SwiftUI

/// A read-only code view that shows line numbers and can highlight specific lines.
struct ConflictCodeView: View {
    @Environment(\.conflictRenderedRows) private var renderedRows
    @Environment(\.conflictHorizontalViewport) private var horizontalViewport
    var minimumCodeWidth: CGFloat = 0

    private var visibleRows: Range<Int> {
        (renderedRows ?? rows.indices).clamped(to: rows.indices)
    }

    private var leadingSpace: CGFloat { CGFloat(visibleRows.lowerBound) * rowHeight }
    private var trailingSpace: CGFloat { CGFloat(rows.count - visibleRows.upperBound) * rowHeight }
    static let defaultFontSize: CGFloat = 12
    static let verticalPadding: CGFloat = 8

    static func rowHeight(fontSize: CGFloat = defaultFontSize) -> CGFloat {
        fontSize + 6
    }

    let fileExtension: String
    let highlightColor: Color
    let fontSize: CGFloat
    let rows: [ConflictCodeLine]
    let selectionSide: ConflictPaneSelectionSide?
    let isSelected: (Int) -> Bool
    let onSelectionChanged: (Int, Bool) -> Void
    let onResolveConflict: (Int, ConflictSectionResolution) -> Void
    let onResolveAll: (ConflictSectionResolution) -> Void

    private var rowHeight: CGFloat {
        Self.rowHeight(fontSize: fontSize)
    }

    init(
        text: String,
        fileExtension: String,
        highlightedLines: Set<Int>,
        highlightColor: Color,
        fontSize: CGFloat = Self.defaultFontSize
    ) {
        var components = text.components(separatedBy: "\n")
        if components.last == "" {
            components.removeLast()
        }

        self.fileExtension = fileExtension
        self.highlightColor = highlightColor
        self.fontSize = fontSize
        self.rows = components.enumerated().map { index, line in
            let lineNumber = index + 1
            return .actual(
                lineNumber: lineNumber,
                text: line,
                isConflict: highlightedLines.contains(lineNumber)
            )
        }
        self.selectionSide = nil
        self.isSelected = { _ in false }
        self.onSelectionChanged = { _, _ in }
        self.onResolveConflict = { _, _ in }
        self.onResolveAll = { _ in }
    }

    init(
        rows: [ConflictCodeLine],
        fileExtension: String,
        highlightColor: Color,
        minimumCodeWidth: CGFloat = 0,
        fontSize: CGFloat = Self.defaultFontSize,
        selectionSide: ConflictPaneSelectionSide? = nil,
        isSelected: @escaping (Int) -> Bool = { _ in false },
        onSelectionChanged: @escaping (Int, Bool) -> Void = { _, _ in },
        onResolveConflict: @escaping (Int, ConflictSectionResolution) -> Void = { _, _ in },
        onResolveAll: @escaping (ConflictSectionResolution) -> Void = { _ in }
    ) {
        self.fileExtension = fileExtension
        self.highlightColor = highlightColor
        self.fontSize = fontSize
        self.rows = rows
        self.minimumCodeWidth = minimumCodeWidth
        self.selectionSide = selectionSide
        self.isSelected = isSelected
        self.onSelectionChanged = onSelectionChanged
        self.onResolveConflict = onResolveConflict
        self.onResolveAll = onResolveAll
    }

    var body: some View {
        HStack(spacing: 0) {
            if selectionSide != nil {
                selectionControls
            }
            lineNumbers
            codeContent
        }
        .overlay(alignment: .topLeading) {
            conflictBlockBorders
        }
    }

    // MARK: - Selection Controls

    private var selectionControls: some View {
        VStack(alignment: .center, spacing: 0) {
            Color.clear.frame(height: leadingSpace)
            ForEach(visibleRows, id: \.self) { index in
                let row = rows[index]
                rowWithContextMenu(for: row) {
                    selectionControl(for: row)
                        .frame(width: 28, height: rowHeight)
                        .background(rowBackground(for: row))
                }
            }
            Color.clear.frame(height: trailingSpace)
        }
        .frame(width: 28)
        .padding(.vertical, Self.verticalPadding)
        .background(.secondary.opacity(0.05))
    }

    // MARK: - Line Numbers

    private var lineNumbers: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Color.clear.frame(height: leadingSpace)
            ForEach(visibleRows, id: \.self) { index in
                let row = rows[index]
                rowWithContextMenu(for: row) {
                    Text(row.lineNumber.map(String.init) ?? "")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
                        .padding(.trailing, 8)
                        .frame(height: rowHeight)
                        .background(rowBackground(for: row))
                }
            }
            Color.clear.frame(height: trailingSpace)
        }
        .frame(width: 48)
        .padding(.vertical, Self.verticalPadding)
        .background(.secondary.opacity(0.05))
    }

    // MARK: - Code Content

    private var codeContent: some View {
        let highlighter = SyntaxHighlighter(fileExtension: fileExtension)

        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: leadingSpace)
            ForEach(visibleRows, id: \.self) { index in
                let row = rows[index]
                rowWithContextMenu(for: row) {
                    Group {
                        if DiffLongLineLayout.isLong(row.text) {
                            DiffLongLineContent(
                                lineID: index, text: row.text,
                                viewport: horizontalViewport.offsetBy(dx: selectionSide == nil ? -56 : -84, dy: 0),
                                fontSize: fontSize
                            )
                        } else {
                            Text(attributedText(for: row, using: highlighter))
                                .font(.system(size: fontSize, design: .monospaced))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                        .background(rowBackground(for: row))
                }
            }
            Color.clear.frame(height: trailingSpace)
        }
        .frame(minWidth: minimumCodeWidth)
        .padding(.vertical, Self.verticalPadding)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func rowWithContextMenu<Content: View>(
        for row: ConflictCodeLine,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if selectionSide == nil {
            content()
        } else {
            content()
                .contentShape(Rectangle())
                .contextMenu {
                    contextMenuItems(for: row)
                }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for row: ConflictCodeLine) -> some View {
        if !row.isPlaceholder {
            Button("Copy line") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.text, forType: .string)
            }
            Divider()
        }
        if row.isConflict, let sectionIndex = row.conflictSectionIndex {
            Button("Take Incoming") {
                onResolveConflict(sectionIndex, .incoming)
            }
            Button("Take Current") {
                onResolveConflict(sectionIndex, .current)
            }
            Divider()
            Button("Take Both (Incoming First)") {
                onResolveConflict(sectionIndex, .bothIncomingFirst)
            }
            Button("Take Both (Current First)") {
                onResolveConflict(sectionIndex, .both)
            }
        } else {
            Button("Take All Incoming") {
                onResolveAll(.incoming)
            }
            Button("Take All Current") {
                onResolveAll(.current)
            }
        }
    }

    @ViewBuilder
    private var conflictBlockBorders: some View {
        if selectionSide != nil {
            GeometryReader { proxy in
                ForEach(visibleConflictRanges, id: \.lowerBound) { range in
                    Rectangle()
                        .stroke(highlightColor.opacity(0.9), lineWidth: 1)
                        .frame(
                            width: proxy.size.width,
                            height: CGFloat(range.count) * rowHeight
                        )
                        .offset(
                            x: 0,
                            y: Self.verticalPadding + CGFloat(range.lowerBound) * rowHeight
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var visibleConflictRanges: [Range<Int>] {
        var ranges: [Range<Int>] = []
        var index = visibleRows.lowerBound
        while index < visibleRows.upperBound {
            guard rows[index].isConflict else { index += 1; continue }
            let start = index
            let section = rows[index].conflictSectionIndex
            repeat { index += 1 }
            while index < visibleRows.upperBound && rows[index].conflictSectionIndex == section
            ranges.append(start..<index)
        }
        return ranges
    }

    @ViewBuilder
    private func selectionControl(for row: ConflictCodeLine) -> some View {
        if let selectionSide,
           let conflictSectionIndex = row.conflictSectionIndex,
           row.startsConflict {
            let selected = isSelected(conflictSectionIndex)

            Button(
                "\(selectionSide.title) conflict block",
                systemImage: selected ? "checkmark.square.fill" : "square"
            ) {
                onSelectionChanged(conflictSectionIndex, !selected)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .accessibilityValue(selected ? "Selected" : "Not selected")
        } else {
            Color.clear
        }
    }

    private func attributedText(
        for row: ConflictCodeLine,
        using highlighter: SyntaxHighlighter
    ) -> AttributedString {
        guard !row.isPlaceholder else { return AttributedString("") }
        return highlighter.attributedString(for: row.text, fontSize: fontSize)
    }

    @ViewBuilder
    private func rowBackground(for row: ConflictCodeLine) -> some View {
        if row.isPlaceholder {
            Color(nsColor: .separatorColor)
                .opacity(0.08)
                .overlay {
                    DiagonalHatchShape()
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
        } else if row.isConflict {
            highlightColor.opacity(0.2)
        } else {
            Color.clear
        }
    }
}
