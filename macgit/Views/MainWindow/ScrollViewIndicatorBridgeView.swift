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

final class ScrollViewIndicatorBridgeView: NSView {
    private static let overflowTolerance: CGFloat = 0.5

    private weak var scrollView: NSScrollView?
    private weak var observedDocumentView: NSView?
    private var controlSize: NSControl.ControlSize?
    private var showsIndicators = false
    private var onScroll: (() -> Void)?
    private var observationTokens: [NSObjectProtocol] = []
    private var resolutionTask: Task<Void, Never>?
    private var indicatorRefreshTask: Task<Void, Never>?
    private var lastContentOffset: CGPoint?
    private var lastContentSize: CGSize?

    func configure(showsIndicators: Bool, controlSize: NSControl.ControlSize?, onScroll: @escaping () -> Void) {
        self.controlSize = controlSize
        self.showsIndicators = showsIndicators
        self.onScroll = onScroll
        resolveScrollView()
        applyIndicatorVisibility()
    }

    func detach() {
        resolutionTask?.cancel()
        resolutionTask = nil
        indicatorRefreshTask?.cancel()
        indicatorRefreshTask = nil
        removeObservers()
        scrollView = nil
        observedDocumentView = nil
        lastContentOffset = nil
        lastContentSize = nil
        onScroll = nil
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
        resolutionTask?.cancel()
        resolutionTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, let resolvedScrollView = findScrollView() else {
                return
            }
            guard scrollView !== resolvedScrollView else {
                installObserversIfNeeded(for: resolvedScrollView)
                applyIndicatorVisibility()
                return
            }

            removeObservers()
            scrollView = resolvedScrollView
            resolvedScrollView.scrollerStyle = .overlay
            resolvedScrollView.autohidesScrollers = false
            lastContentOffset = resolvedScrollView.contentView.bounds.origin
            installObserversIfNeeded(for: resolvedScrollView)
            applyIndicatorVisibility()
        }
    }

    private func installObserversIfNeeded(for scrollView: NSScrollView) {
        guard observationTokens.isEmpty || observedDocumentView !== scrollView.documentView else {
            return
        }

        removeObservers()

        let contentView = scrollView.contentView
        let documentView = scrollView.documentView
        contentView.postsBoundsChangedNotifications = true
        contentView.postsFrameChangedNotifications = true
        documentView?.postsBoundsChangedNotifications = true
        documentView?.postsFrameChangedNotifications = true
        observedDocumentView = documentView
        lastContentOffset = contentView.bounds.origin
        lastContentSize = contentView.bounds.size

        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self] _ in
                self?.contentOffsetDidChange()
            }
        )

        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleIndicatorRefresh()
            }
        )

        guard let documentView else { return }
        for notificationName in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
            observationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: notificationName,
                    object: documentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleIndicatorRefresh()
                }
            )
        }
    }

    private func removeObservers() {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observationTokens.removeAll()
    }

    private func findScrollView() -> NSScrollView? {
        if let enclosingScrollView {
            return enclosingScrollView
        }

        var ancestor = superview
        while let candidateRoot = ancestor {
            if let match = candidateRoot.descendantScrollViews.first(where: containsBridgeCenter) {
                return match
            }
            ancestor = candidateRoot.superview
        }
        return nil
    }

    private func containsBridgeCenter(_ candidate: NSScrollView) -> Bool {
        guard candidate.window === window else { return false }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        return candidate.bounds.contains(candidate.convert(center, from: self))
    }

    private func contentOffsetDidChange() {
        guard let scrollView else { return }
        let contentOffset = scrollView.contentView.bounds.origin
        // Scrolling (including elastic overscroll) changes the origin, not
        // the viewport size. Only resize events need scroller configuration.
        let contentSize = scrollView.contentView.bounds.size
        if contentSize != lastContentSize {
            lastContentSize = contentSize
            scheduleIndicatorRefresh()
        }
        guard contentOffset != lastContentOffset else { return }
        lastContentOffset = contentOffset
        onScroll?()
    }

    private func scheduleIndicatorRefresh() {
        indicatorRefreshTask?.cancel()
        indicatorRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.applyIndicatorVisibility()
        }
    }

    private func applyIndicatorVisibility() {
        guard let scrollView else { return }
        let contentView = scrollView.contentView
        let hasVerticalOverflow = contentView.documentRect.height
            > contentView.bounds.height + Self.overflowTolerance
        let shouldShowIndicator = hasVerticalOverflow && showsIndicators

        // Keep an overflowing list's overlay scroller installed at all times so
        // hover changes never alter the List's available content width.
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = false
        }
        if scrollView.hasVerticalScroller != hasVerticalOverflow {
            scrollView.hasVerticalScroller = hasVerticalOverflow
        }
        if let controlSize, scrollView.verticalScroller?.controlSize != controlSize {
            scrollView.verticalScroller?.controlSize = controlSize
        }
        let hidesIndicator = !shouldShowIndicator
        if scrollView.verticalScroller?.isHidden != hidesIndicator {
            scrollView.verticalScroller?.isHidden = hidesIndicator
        }

        let indicatorAlpha: CGFloat = shouldShowIndicator ? 1 : 0
        if scrollView.verticalScroller?.alphaValue != indicatorAlpha {
            scrollView.verticalScroller?.alphaValue = indicatorAlpha
        }
    }
}

private extension NSView {
    var descendantScrollViews: [NSScrollView] {
        subviews.flatMap { subview in
            var matches = subview.descendantScrollViews
            if let scrollView = subview as? NSScrollView {
                matches.insert(scrollView, at: 0)
            }
            return matches
        }
    }
}

