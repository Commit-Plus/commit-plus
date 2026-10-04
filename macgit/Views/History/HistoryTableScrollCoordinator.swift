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
import AppKit
import QuartzCore
import SwiftUI

struct HistoryTableViewportAnchor: Equatable {
    let commitHash: String
    let rowOffset: CGFloat
}

@MainActor
final class HistoryTableScrollCoordinator {
    private weak var tableView: NSTableView?
    private weak var observedClipView: NSClipView?
    private let defaults: UserDefaults
    private let layoutKey = "history.tableColumnLayout"
    private var columnLayout: HistoryTableColumnLayout?
    private let initialColumnRatios: [String: Double]
    private var viewportObservers: [NSObjectProtocol] = []
    private var lastVisibleColumns: [String] = []
    private var appliedWidths: [String: CGFloat] = [:]
    private var columnResizeObserver: NSObjectProtocol?
    private var restoreWidthsTask: Task<Void, Never>?
    private var isRestoringWidths = false
    private var contextClickMonitor: Any?
    private let dragPreviewDataSource = HistoryDragPreviewDataSource()
    private var lastViewportOriginY: CGFloat?
    private var lastScrollActivity = Date.distantPast

    func prepareDragPreview(_ presentation: CommitDragPreviewPresentation) {
        guard let tableView else { return }
        installDragPreviewDataSource(on: tableView)
        dragPreviewDataSource.prepare(presentation, in: tableView)
    }

    private func installDragPreviewDataSource(on tableView: NSTableView) {
        guard tableView.dataSource !== dragPreviewDataSource else { return }
        dragPreviewDataSource.original = tableView.dataSource
        tableView.dataSource = dragPreviewDataSource
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initial = ["graph": 0.20, "message": 0.40, "author": 0.18, "date": 0.14, "commit": 0.08]
        let saved = defaults.dictionary(forKey: "history.tableColumnRatios") as? [String: Double]
        let legacy = defaults.dictionary(forKey: "history.tableColumnWidths") as? [String: Double]
        let valid = (saved ?? legacy ?? initial).filter {
            initial[$0.key] != nil && $0.value.isFinite && $0.value > 0
        }
        let total = valid.values.reduce(0, +)
        // Older layouts have no Graph column. Reserve its default share and
        // preserve the relative proportions of the user's existing columns.
        let savedShare = valid["graph"] == nil ? 1 - initial["graph"]! : 1
        initialColumnRatios = initial.merging(valid.mapValues { $0 / max(total, 1e-9) * savedShare }) { _, saved in saved }
        if let data = defaults.data(forKey: layoutKey),
           let layout = try? JSONDecoder().decode(HistoryTableColumnLayout.self, from: data),
           layout.isValid {
            columnLayout = layout
        }
    }

    deinit {
        if let contextClickMonitor {
            NSEvent.removeMonitor(contextClickMonitor)
        }
        restoreWidthsTask?.cancel()
        if let columnResizeObserver {
            NotificationCenter.default.removeObserver(columnResizeObserver)
        }
        for observer in viewportObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @discardableResult
    func attach(from view: NSView) -> Bool {
        var candidate = view.superview
        while let current = candidate {
            if let tableView = current as? NSTableView {
                if self.tableView !== tableView {
                    self.tableView = tableView
                    lastVisibleColumns = []
                    appliedWidths = [:]
                    tableView.columnAutoresizingStyle = .noColumnAutoresizing
                    observeColumnResizing(of: tableView)
                    restoreSavedWidths()
                }
                observeViewport(of: tableView)
                installDragPreviewDataSource(on: tableView)
                restoreVisibleColumnsIfNeeded()
                return true
            }
            candidate = current.superview
        }
        return false
    }

    private func observeColumnResizing(of tableView: NSTableView) {
        if let columnResizeObserver {
            NotificationCenter.default.removeObserver(columnResizeObserver)
        }
        columnResizeObserver = NotificationCenter.default.addObserver(
            forName: tableView is NSOutlineView
                ? NSOutlineView.columnDidResizeNotification
                : NSTableView.columnDidResizeNotification,
            object: tableView,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      !self.isRestoringWidths,
                      let tableView = self.tableView else { return }

                // The final resize notification can arrive after header tracking
                // ends. Its column remains authoritative even when resizedColumn
                // has already returned to -1.
                let index: Int
                if let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn {
                    guard let columnIndex = tableView.tableColumns.firstIndex(where: { $0 === column }) else { return }
                    index = columnIndex
                } else {
                    guard let headerView = tableView.headerView,
                          headerView.resizedColumn >= 0 else { return }
                    index = headerView.resizedColumn
                }

                self.restoreWidthsTask?.cancel()
                self.captureColumnResize(in: tableView, index: index)
            }
        }
    }

    private func observeViewport(of tableView: NSTableView) {
        let clipView = tableView.enclosingScrollView?.contentView
        guard observedClipView !== clipView else { return }
        observedClipView = clipView
        for observer in viewportObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        viewportObservers = []
        guard let clipView else { return }
        clipView.postsFrameChangedNotifications = true
        clipView.postsBoundsChangedNotifications = true
        for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
            viewportObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: clipView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.recordScrollActivityIfNeeded(in: clipView)
                }
            })
        }
    }

    private func recordScrollActivityIfNeeded(in clipView: NSClipView) {
        let originY = clipView.bounds.origin.y
        defer { lastViewportOriginY = originY }
        guard let lastViewportOriginY,
              abs(lastViewportOriginY - originY) > 0.01 else { return }
        lastScrollActivity = Date()
    }

    func waitForScrollingToSettle() async {
        let quietInterval: TimeInterval = 0.18
        while true {
            let remaining = quietInterval - Date().timeIntervalSince(lastScrollActivity)
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
        }
    }

    func visibleRowRange() -> Range<Int>? {
        guard let tableView,
              let clipView = tableView.enclosingScrollView?.contentView else {
            return nil
        }

        let rows = tableView.rows(in: clipView.bounds)
        guard rows.location != NSNotFound, rows.length > 0 else { return nil }
        return rows.location..<(rows.location + rows.length)
    }

    private var visibleColumns: [NSTableColumn] {
        tableView?.tableColumns.filter { !$0.isHidden && Self.columnKey($0) != nil } ?? []
    }

    private func availableWidth(for columns: [NSTableColumn]) -> CGFloat {
        guard let tableView, let clipView = tableView.enclosingScrollView?.contentView else { return 0 }
        // AppKit includes an intercell gap in each column's horizontal extent.
        return max(0, clipView.bounds.width - CGFloat(columns.count) * tableView.intercellSpacing.width)
    }

    private func restoreVisibleColumnsIfNeeded() {
        guard !isRestoringWidths, let tableView,
              let clipView = tableView.enclosingScrollView?.contentView,
              clipView.bounds.width > 0 else { return }
        let keys = visibleColumns.compactMap(Self.columnKey)
        guard keys != lastVisibleColumns else { return }
        applyColumnWidths()
    }

    private func applyColumnWidths() {
        // Scroller tiling can notify viewport changes before AppKit publishes
        // the dragged column's new width. Never restore stale widths mid-drag.
        guard (tableView?.headerView?.resizedColumn ?? -1) < 0 else { return }
        let columns = visibleColumns
        guard !columns.isEmpty,
              let viewportWidth = tableView?.enclosingScrollView?.contentView.bounds.width,
              viewportWidth > 0, availableWidth(for: columns) > 0 else { return }
        if columnLayout == nil {
            // Convert old proportions once, using the first available viewport.
            // Keep this reference unchanged during subsequent window resizing.
            columnLayout = HistoryTableColumnLayout(
                widths: initialColumnRatios.mapValues { $0 * Double(availableWidth(for: columns)) },
                viewportWidth: Double(viewportWidth)
            )
            saveColumnLayout()
        }
        guard let columnLayout else { return }
        let widths = columns.map { column in
            CGFloat(columnLayout.width(
                for: Self.columnKey(column)!,
                minimumWidth: Double(column.minWidth)
            ))
        }
        setWidths(widths, for: columns)
    }

    private func captureColumnResize(in tableView: NSTableView, index: Int) {
        guard tableView.tableColumns.indices.contains(index),
              let viewportWidth = tableView.enclosingScrollView?.contentView.bounds.width,
              viewportWidth > 0 else { return }
        let columns = visibleColumns
        guard let active = columns.firstIndex(where: { $0 === tableView.tableColumns[index] }),
              columnLayout != nil else { return }
        var widths = columns.map { appliedWidths[Self.columnKey($0)!] ?? $0.width }
        widths[active] = max(columns[active].minWidth, columns[active].width)
        columnLayout?.resizeColumn(
            Self.columnKey(columns[active])!,
            to: Double(widths[active]),
            viewportWidth: Double(viewportWidth)
        )
        // AppKit owns layout during header tracking. Retiling from inside its
        // resize notification re-enters scroller layout at the overflow boundary.
        // Record the new width without writing column widths back to AppKit.
        for (column, width) in zip(columns, widths) {
            appliedWidths[Self.columnKey(column)!] = width
        }
        lastVisibleColumns = columns.compactMap(Self.columnKey)
        saveColumnLayout()
    }

    private func saveColumnLayout() {
        guard let columnLayout,
              let data = try? JSONEncoder().encode(columnLayout) else { return }
        defaults.set(data, forKey: layoutKey)
    }

    private func setWidths(_ widths: [CGFloat], for columns: [NSTableColumn]) {
        guard let tableView else { return }
        isRestoringWidths = true
        defer { isRestoringWidths = false }
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.enclosingScrollView?.hasHorizontalScroller = true
        for (column, width) in zip(columns, widths) {
            // Keep absolute widths during viewport and scroller changes.
            column.resizingMask = .userResizingMask
            if abs(column.width - width) > 0.01 {
                column.width = width
            }
            appliedWidths[Self.columnKey(column)!] = column.width
        }
        tableView.tile()
        lastVisibleColumns = columns.compactMap(Self.columnKey)
    }

    private func restoreSavedWidths() {
        restoreWidthsTask?.cancel()
        restoreWidthsTask = Task { @MainActor [weak self] in
            // SwiftUI can configure columns after cells first attach.
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled, let self, let tableView = self.tableView else { return }
                guard tableView.window != nil else { continue }
                tableView.layoutSubtreeIfNeeded()
                self.observeViewport(of: tableView)
                guard !self.visibleColumns.isEmpty,
                      (tableView.headerView?.resizedColumn ?? -1) < 0,
                      self.availableWidth(for: self.visibleColumns) > 0 else { continue }
                self.applyColumnWidths()
                return
            }
        }
    }

    private static func columnKey(_ column: NSTableColumn) -> String? {
        // SwiftUI's native identifiers are fresh UUIDs on every mount. Header
        // titles remain stable even when the user reorders or hides columns.
        let key = column.title.lowercased()
        return ["graph", "message", "author", "date", "commit"].contains(key) ? key : nil
    }

    // Rows outside the scroll viewport still have frames. A contextual click
    // must belong to the visible table, not merely map to one of those rows.
    private func containsContextClick(_ event: NSEvent) -> Bool {
        guard let tableView,
              let window = tableView.window,
              event.window === window,
              tableView.visibleRect.contains(tableView.convert(event.locationInWindow, from: nil)),
              let contentView = window.contentView,
              let hitView = contentView.hitTest(
                contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
              ) else { return false }
        return hitView === tableView || hitView.isDescendant(of: tableView)
    }

    var allowsContextMenu: Bool {
        guard let event = NSApp.currentEvent else { return true }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .leftMouseDown, .leftMouseUp:
            return containsContextClick(event)
        default:
            return true
        }
    }

    func startContextClickMonitoring(onRow: @escaping (Int) -> Void) {
        stopContextClickMonitoring()
        contextClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                      let tableView = self?.tableView,
                      self?.containsContextClick(event) == true else {
                    return event
                }
                let row = tableView.row(at: tableView.convert(event.locationInWindow, from: nil))
                guard row >= 0 else { return event }
                // Update selection before AppKit dispatches the context menu.
                onRow(row)
                return event
            }
        }
    }

    func stopContextClickMonitoring() {
        if let contextClickMonitor {
            NSEvent.removeMonitor(contextClickMonitor)
            self.contextClickMonitor = nil
        }
    }

    func isContextClick(onRows selectedRows: IndexSet) -> Bool {
        guard let tableView,
              let event = NSApp.currentEvent,
              event.window === tableView.window else { return false }
        let isContextClick = event.type == .rightMouseDown
            || event.type == .rightMouseUp
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isContextClick, containsContextClick(event) else { return false }
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)
        return row >= 0 && selectedRows.contains(row)
    }

    func scrollToRowWhenReady(_ row: Int) async {
        for _ in 0..<30 {
            if scrollToRow(row) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func focusTableWhenReady() async {
        await Task.yield()
        for _ in 0..<30 {
            if let tableView,
               let window = tableView.window,
               window.makeFirstResponder(tableView) {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
        }
    }

    func viewportAnchor(commitHashes: [String]) -> HistoryTableViewportAnchor? {
        guard let tableView,
              let clipView = tableView.enclosingScrollView?.contentView else {
            return nil
        }

        let visibleRows = tableView.rows(in: clipView.bounds)
        guard visibleRows.location != NSNotFound,
              visibleRows.length > 0,
              commitHashes.indices.contains(visibleRows.location) else {
            return nil
        }

        let row = visibleRows.location
        return HistoryTableViewportAnchor(
            commitHash: commitHashes[row],
            rowOffset: tableView.rect(ofRow: row).minY - clipView.bounds.minY
        )
    }

    func restoreViewportAnchor(
        _ anchor: HistoryTableViewportAnchor,
        commitHashes: [String]
    ) async {
        guard let row = commitHashes.firstIndex(of: anchor.commitHash) else { return }

        for _ in 0..<30 {
            guard let tableView,
                  tableView.numberOfRows > row,
                  let clipView = tableView.enclosingScrollView?.contentView else {
                try? await Task.sleep(nanoseconds: 10_000_000)
                continue
            }

            let maximumY = max(0, tableView.bounds.height - clipView.bounds.height)
            let targetY = min(
                maximumY,
                max(0, tableView.rect(ofRow: row).minY - anchor.rowOffset)
            )
            clipView.setBoundsOrigin(
                CGPoint(x: clipView.bounds.origin.x, y: targetY)
            )
            tableView.enclosingScrollView?.reflectScrolledClipView(clipView)
            return
        }
    }

    @discardableResult
    private func scrollToRow(_ row: Int) -> Bool {
        guard let tableView,
              tableView.numberOfRows > row,
              row >= 0,
              let scrollView = tableView.enclosingScrollView else {
            return false
        }

        let rowRect = tableView.rect(ofRow: row)
        let clipView = scrollView.contentView
        guard !clipView.bounds.intersects(rowRect) else { return true }

        let maximumY = max(0, tableView.bounds.height - clipView.bounds.height)
        let targetY = min(
            maximumY,
            max(0, rowRect.midY - clipView.bounds.height / 2)
        )
        let targetOrigin = CGPoint(x: clipView.bounds.origin.x, y: targetY)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clipView.animator().setBoundsOrigin(targetOrigin)
        }
        return true
    }
}

struct HistoryTableIntrospectionView: NSViewRepresentable {
    let coordinator: HistoryTableScrollCoordinator

    func makeNSView(context: Context) -> HistoryTableIntrospectionNSView {
        HistoryTableIntrospectionNSView(coordinator: coordinator)
    }

    func updateNSView(_ nsView: HistoryTableIntrospectionNSView, context: Context) {
        nsView.coordinator = coordinator
        nsView.attachIfPossible()
    }
}

final class HistoryTableIntrospectionNSView: NSView {
    weak var coordinator: HistoryTableScrollCoordinator?
    private var attachRetryCount = 0

    init(coordinator: HistoryTableScrollCoordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfPossible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfPossible()
    }

    func attachIfPossible() {
        guard let coordinator else { return }
        if coordinator.attach(from: self) {
            attachRetryCount = 0
        } else if attachRetryCount < 30 {
            attachRetryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.attachIfPossible()
            }
        }
    }
}
