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

private struct ConflictRenderedRowsKey: EnvironmentKey {
    static let defaultValue: Range<Int>? = nil
}

extension EnvironmentValues {
    var conflictRenderedRows: Range<Int>? {
        get { self[ConflictRenderedRowsKey.self] }
        set { self[ConflictRenderedRowsKey.self] = newValue }
    }
}

struct SyncedScrollView<Content: View>: View {
    let id: String
    let controller: SyncedScrollController
    let axes: Axis.Set
    let showsIndicators: Bool
    let virtualizedRowCount: Int?
    @State private var renderedRows = 0..<500
    @ViewBuilder let content: Content

    init(
        id: String,
        controller: SyncedScrollController,
        axes: Axis.Set = [.horizontal, .vertical],
        showsIndicators: Bool = true,
        virtualizedRowCount: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.controller = controller
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.virtualizedRowCount = virtualizedRowCount
        self.content = content()
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content
                .environment(\.conflictRenderedRows, virtualizedRowCount == nil ? nil : renderedRows)
                .background(
                    SyncedScrollConnector(id: id, controller: controller)
                )
        }
        .onScrollGeometryChange(for: Range<Int>.self) { geometry in
            ConflictRenderWindow.rows(
                count: virtualizedRowCount ?? 0,
                minY: geometry.visibleRect.minY,
                height: geometry.visibleRect.height
            )
        } action: { _, range in
            renderedRows = range
        }
    }
}

private struct SyncedScrollConnector: NSViewRepresentable {
    let id: String
    let controller: SyncedScrollController

    func makeNSView(context: Context) -> SyncedScrollBridgeView {
        let view = SyncedScrollBridgeView()
        view.configure(id: id, controller: controller)
        return view
    }

    func updateNSView(_ nsView: SyncedScrollBridgeView, context: Context) {
        nsView.configure(id: id, controller: controller)
    }

    static func dismantleNSView(_ nsView: SyncedScrollBridgeView, coordinator: ()) {
        nsView.detach()
    }
}

private final class SyncedScrollBridgeView: NSView {
    private var id: String?
    private weak var controller: SyncedScrollController?
    private weak var scrollView: NSScrollView?

    func configure(id: String, controller: SyncedScrollController) {
        if self.id != id {
            detach()
        }

        self.id = id
        self.controller = controller
        resolveScrollView()
    }

    func detach() {
        guard let id, let scrollView else { return }
        controller?.unregister(id: id, scrollView: scrollView)
        self.scrollView = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveScrollView()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        resolveScrollView()
    }

    private func resolveScrollView() {
        DispatchQueue.main.async { [weak self] in
            self?.attachToEnclosingScrollView()
        }
    }

    private func attachToEnclosingScrollView() {
        guard let id, let controller else { return }
        guard let enclosingScrollView else { return }

        if scrollView !== enclosingScrollView {
            if let scrollView {
                controller.unregister(id: id, scrollView: scrollView)
            }

            scrollView = enclosingScrollView
            controller.register(enclosingScrollView, id: id)
        }
    }
}
