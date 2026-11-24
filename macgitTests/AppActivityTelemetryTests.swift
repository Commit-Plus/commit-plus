// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import macgit

@MainActor
final class AppActivityTelemetryTests: XCTestCase {
    func testRepeatedActivationAndInputAcrossWindowsSendOnlyOncePerDay() {
        var signals = 0
        let controller = AppActivityTelemetryController(
            now: { Date(timeIntervalSince1970: 86_400 * 20_000) },
            sendActivity: { signals += 1 }
        )
        for _ in 0..<100 {
            controller.recordActivity(isActive: true)
        }
        XCTAssertEqual(signals, 1)
    }

    func testForegroundInteractionAfterUTCMidnightReportsNewDay() {
        var date = Date(timeIntervalSince1970: 86_400 * 20_000 - 1)
        var signals = 0
        let controller = AppActivityTelemetryController(now: { date }, sendActivity: { signals += 1 })
        controller.recordActivity(isActive: true)
        date.addTimeInterval(2)
        XCTAssertEqual(signals, 1, "The passage of time must not generate activity")
        controller.recordActivity(isActive: true)
        controller.recordActivity(isActive: true)
        XCTAssertEqual(signals, 2)
    }

    func testInactiveDaysAreNotCountedOrBackfilled() {
        var date = Date(timeIntervalSince1970: 86_400 * 20_000)
        var signals = 0
        let controller = AppActivityTelemetryController(now: { date }, sendActivity: { signals += 1 })
        controller.recordActivity(isActive: false)
        XCTAssertEqual(signals, 0)
        controller.recordActivity(isActive: true)
        for _ in 0..<5 {
            date.addTimeInterval(86_400)
            controller.recordActivity(isActive: false)
        }
        XCTAssertEqual(signals, 1)
        controller.recordActivity(isActive: true)
        XCTAssertEqual(signals, 2)
    }

    func testNewProcessCanReportAgainWithoutPersistedSuppression() {
        var signals = 0
        for _ in 0..<2 {
            let controller = AppActivityTelemetryController(
                now: { Date(timeIntervalSince1970: 86_400 * 20_000) },
                sendActivity: { signals += 1 }
            )
            controller.recordActivity(isActive: true)
        }
        XCTAssertEqual(signals, 2, "DAU deduplicates the SDK's stable identifier, not event count")
    }
}
