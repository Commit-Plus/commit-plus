// SPDX-License-Identifier: AGPL-3.0-or-later

import FirebaseAnalytics
import FirebaseCore
import Foundation

@MainActor
enum AppTelemetry {
    static let activityEventName = "app_active"

    /// Collection is off by default in Info.plist so unit-test hosts and previews never report.
    /// The persisted setting is written on every launch, so a test run cannot inherit a prior `true`.
    static func makeActivityController() -> AppActivityTelemetryController? {
        guard FirebaseApp.app() != nil else { return nil }
        let shouldCollect = !FirebaseBootstrap.isRunningUnitTests
            && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"

        // Debug usage deliberately counts alongside Release usage.
        Analytics.setAnalyticsCollectionEnabled(shouldCollect)
        guard shouldCollect else { return nil }

        return AppActivityTelemetryController {
            Analytics.logEvent(activityEventName, parameters: nil)
        }
    }
}
