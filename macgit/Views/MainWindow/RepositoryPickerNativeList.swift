// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct RepositoryPickerNativeList<Content: View>: NSViewRepresentable {
    typealias Row = RepositoryPickerListItem

    let rows: [Row]
    let textScale: CGFloat
    let dark: Bool
    @ViewBuilder let content: (Row) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.apply(self) }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private let table = NSTableView()
        private var model: RepositoryPickerNativeList?
        private var rows: [Row] = []

        func makeScrollView() -> NSScrollView {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.automaticallyAdjustsContentInsets = false
            let column = NSTableColumn(identifier: .init("repository"))
            column.resizingMask = .autoresizingMask
            table.addTableColumn(column)
            table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            table.autoresizingMask = [.width]
            table.headerView = nil
            table.style = .plain
            table.backgroundColor = .clear
            table.selectionHighlightStyle = .none
            table.intercellSpacing = .zero
            table.usesAutomaticRowHeights = true
            table.rowHeight = 68
            table.dataSource = self
            table.delegate = self
            scroll.documentView = table
            return scroll
        }

        func apply(_ next: RepositoryPickerNativeList) {
            let old = rows
            let appearanceChanged = model?.textScale != next.textScale || model?.dark != next.dark
            model = next
            rows = next.rows
            table.enclosingScrollView?.appearance = NSAppearance(named: next.dark ? .darkAqua : .aqua)
            if old.map(\.id) != rows.map(\.id) || appearanceChanged {
                let visible = table.rows(in: table.visibleRect)
                let anchor = visible.location != NSNotFound && old.indices.contains(visible.location) ? old[visible.location].id : nil
                let offset = anchor == nil ? 0 : table.visibleRect.minY - table.rect(ofRow: visible.location).minY
                table.reloadData()
                table.layoutSubtreeIfNeeded()
                if let anchor, let index = rows.firstIndex(where: { $0.id == anchor }), let scroll = table.enclosingScrollView {
                    scroll.contentView.scroll(to: .init(x: 0, y: max(0, table.rect(ofRow: index).minY + offset)))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            } else {
                let changed = IndexSet(rows.indices.filter { rows[$0] != old[$0] })
                if !changed.isEmpty {
                    table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
                    table.noteHeightOfRows(withIndexesChanged: changed)
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let model else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("RepositoryPickerCell")
            let content = model.content(rows[row])
            if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? RepositoryPickerHostingCell<Content> {
                cell.host.rootView = content
                return cell
            }
            let cell = RepositoryPickerHostingCell(content: content)
            cell.identifier = identifier
            return cell
        }
    }
}

private final class RepositoryPickerHostingCell<Content: View>: NSTableCellView {
    let host: NSHostingView<Content>
    init(content: Content) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor), host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
