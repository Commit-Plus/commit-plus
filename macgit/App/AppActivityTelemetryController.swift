// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit

/// One tracker for the whole application, independent of repository windows.
@MainActor
final class AppActivityTelemetryController {
    private let now: () -> Date
    private let sendActivity: () -> Void
    private var lastReportedDay: Int?
    private var eventMonitor: Any?

    init(now: @escaping () -> Date = { .now }, sendActivity: @escaping () -> Void) {
        self.now = now
        self.sendActivity = sendActivity
    }

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            // Observe activity only; never inspect or retain the input's contents.
            self?.recordActivity(isActive: NSApp.isActive)
            return event
        }
        recordActivity(isActive: NSApp.isActive)
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    func recordActivity(isActive: Bool) {
        guard isActive else { return }
        // UTC buckets match the documented reporting timezone, even after travel.
        let day = Int(floor(now().timeIntervalSince1970 / 86_400))
        guard day != lastReportedDay else { return }
        lastReportedDay = day
        sendActivity()
    }
}
