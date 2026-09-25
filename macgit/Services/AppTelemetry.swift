// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import TelemetryDeck

@MainActor
enum AppTelemetry {
    static func makeActivityController(bundle: Bundle = .main) -> AppActivityTelemetryController? {
        guard !FirebaseBootstrap.isRunningUnitTests,
              ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              let url = bundle.url(forResource: "TelemetryDeck-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let appID = appID(from: data) else {
            return nil
        }

        let config = TelemetryDeck.Config(appID: appID)
        // Debug usage deliberately counts alongside Release usage.
        config.testMode = false
        config.sendNewSessionBeganSignal = false
        config.sessionStatsEnabled = false
        TelemetryDeck.initialize(config: config)
        return AppActivityTelemetryController {
            TelemetryDeck.signal("App.active")
        }
    }

    static func appID(from data: Data) -> String? {
        guard let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = values["AppID"] as? String,
              let uuid = UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              uuid.uuidString != "00000000-0000-0000-0000-000000000000" else {
            return nil
        }
        return uuid.uuidString
    }
}
