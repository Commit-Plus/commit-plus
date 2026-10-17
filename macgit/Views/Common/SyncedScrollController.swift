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

final class SyncedScrollController {
    private struct PendingScroll {
        var sourceID: String
        var origin: CGPoint
        var syncsHorizontally: Bool
        var syncsVertically: Bool
    }

    private var scrollViews: [String: WeakScrollView] = [:]
    private var observers: [String: NSObjectProtocol] = [:]
    private var lastKnownOrigins: [String: CGPoint] = [:]
    private var isApplyingSynchronizedScroll = false
    private var lastRequestedOffset: CGFloat?
    private var pendingScroll: PendingScroll?
    private var pendingScrollWorkItem: DispatchWorkItem?

    func register(_ scrollView: NSScrollView, id: String) {
        removeReleasedScrollViews()

        if scrollViews[id]?.value === scrollView {
            return
        }

        unregister(id: id)
        scrollViews[id] = WeakScrollView(scrollView)
        lastKnownOrigins[id] = scrollView.contentView.bounds.origin

        scrollView.contentView.postsBoundsChangedNotifications = true
        observers[id] = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            guard let self, let scrollView else { return }
            self.syncScroll(from: id, source: scrollView)
        }

        // If a scroll offset was requested before this scroll view finished
        // registering, apply it now so callers can scroll before the bridge
        // between SwiftUI and AppKit is fully wired up.
        if let lastRequestedOffset {
            setVerticalOffset(lastRequestedOffset, on: scrollView)
            lastKnownOrigins[id] = scrollView.contentView.bounds.origin
        }
    }

    func unregister(id: String, scrollView: NSScrollView? = nil) {
        if let scrollView, scrollViews[id]?.value !== scrollView {
            return
        }

        if let observer = observers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        scrollViews.removeValue(forKey: id)
        lastKnownOrigins.removeValue(forKey: id)
    }

    func scrollToTop() {
        scrollToVerticalOffset(0)
    }

    func scrollToVerticalOffset(_ offset: CGFloat) {
        removeReleasedScrollViews()
        pendingScrollWorkItem?.cancel()
        pendingScrollWorkItem = nil
        pendingScroll = nil
        lastRequestedOffset = offset
        isApplyingSynchronizedScroll = true
        for (id, weakScrollView) in scrollViews {
            guard let scrollView = weakScrollView.value else { continue }
            setVerticalOffset(offset, on: scrollView)
            lastKnownOrigins[id] = scrollView.contentView.bounds.origin
        }
        isApplyingSynchronizedScroll = false
    }

    private func syncScroll(from sourceID: String, source: NSScrollView) {
        guard !isApplyingSynchronizedScroll else { return }
        removeReleasedScrollViews()

        let sourceOrigin = source.contentView.bounds.origin
        let previousOrigin = lastKnownOrigins[sourceID] ?? sourceOrigin
        let didScrollHorizontally = abs(sourceOrigin.x - previousOrigin.x) > 0.5
        let didScrollVertically = abs(sourceOrigin.y - previousOrigin.y) > 0.5

        guard didScrollHorizontally || didScrollVertically else { return }
        lastKnownOrigins[sourceID] = sourceOrigin

        if var pendingScroll, pendingScroll.sourceID == sourceID {
            pendingScroll.origin = sourceOrigin
            pendingScroll.syncsHorizontally = pendingScroll.syncsHorizontally
                || didScrollHorizontally
            pendingScroll.syncsVertically = pendingScroll.syncsVertically
                || didScrollVertically
            self.pendingScroll = pendingScroll
        } else {
            pendingScroll = PendingScroll(
                sourceID: sourceID,
                origin: sourceOrigin,
                syncsHorizontally: didScrollHorizontally,
                syncsVertically: didScrollVertically
            )
        }

        schedulePendingScroll()
    }

    private func schedulePendingScroll() {
        guard pendingScrollWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingScrollWorkItem = nil
            self.applyPendingScroll()
        }
        pendingScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: workItem)
    }

    private func applyPendingScroll() {
        guard let pendingScroll else { return }
        self.pendingScroll = nil
        isApplyingSynchronizedScroll = true

        for (id, weakScrollView) in scrollViews where id != pendingScroll.sourceID {
            guard let scrollView = weakScrollView.value else { continue }
            var targetOrigin = scrollView.contentView.bounds.origin
            if pendingScroll.syncsHorizontally {
                targetOrigin.x = pendingScroll.origin.x
            }
            if pendingScroll.syncsVertically {
                targetOrigin.y = pendingScroll.origin.y
            }
            setScrollOrigin(targetOrigin, on: scrollView)
            lastKnownOrigins[id] = scrollView.contentView.bounds.origin
        }

        isApplyingSynchronizedScroll = false
    }

    private func setScrollOrigin(_ origin: CGPoint, on scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }

        let maximumX = max(0, documentView.bounds.width - scrollView.contentView.bounds.width)
        let maximumY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        let clampedOrigin = CGPoint(
            x: min(max(0, origin.x), maximumX),
            y: min(max(0, origin.y), maximumY)
        )

        let currentOrigin = scrollView.contentView.bounds.origin
        guard abs(clampedOrigin.x - currentOrigin.x) > 0.5
                || abs(clampedOrigin.y - currentOrigin.y) > 0.5 else {
            return
        }

        scrollView.contentView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func setVerticalOffset(_ offset: CGFloat, on scrollView: NSScrollView) {
        var origin = scrollView.contentView.bounds.origin
        origin.y = offset
        setScrollOrigin(origin, on: scrollView)
    }

    private func removeReleasedScrollViews() {
        let releasedIDs = scrollViews.compactMap { id, weakScrollView in
            weakScrollView.value == nil ? id : nil
        }

        for id in releasedIDs {
            unregister(id: id)
        }
    }
}

private final class WeakScrollView {
    weak var value: NSScrollView?

    init(_ value: NSScrollView) {
        self.value = value
    }
}
