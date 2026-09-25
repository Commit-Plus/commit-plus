# App activity telemetry

Commit+ uses TelemetryDeck Swift SDK 2.14.2 to send `App.active` without custom parameters. It uses the SDK's default anonymous installation/device identifier, with no account ID, email, repository name/path, filename, source code, commit message, branch, remote URL, or AI content supplied to telemetry. The SDK adds its standard app/device metadata and handles hashing, buffering, and network retries.

## Configuration

Run `TELEMETRYDECK_APP_ID='<your-app-id>' python3 scripts/release/write-telemetry-config.py` from the repository root. This writes the gitignored `macgit/TelemetryDeck-Info.plist` resource. App startup reads `AppID` from that file; missing or invalid configuration disables telemetry without blocking the app.

The release workflow generates this resource from the GitHub repository variable `TELEMETRYDECK_APP_ID`, failing before the build if it is missing or invalid. No production ID is stored in tracked source.

Debug and Release intentionally share production analytics (`testMode = false`). Unit-test hosts and SwiftUI previews do not initialize the SDK. Automatic session signals and session statistics are disabled.

## Activity definition

One app-level controller observes application activation and local key-down, mouse-down, and scroll events. Input is returned unchanged; event contents are never inspected, stored, or sent. This includes Welcome and repository windows without per-window observers.

Within each app process, at most one signal is queued per UTC day. The first foreground interaction after midnight counts even if the app never lost focus. Merely staying open, sleeping/waking, or refreshing Git in the background generates no activity. Missed days are never backfilled.

The daily gate is intentionally in memory: relaunching can send another signal for the same day, allowing another opportunity to report after an interrupted launch. TelemetryDeck deduplicates the stable user identifier when counting users. Delivery is best-effort; offline or abruptly terminated sessions are not guaranteed to appear.

## Dashboard and acceptance

Filter insights to `App.active`, production signals, and this app. Use **Count Users**, not Count Signals, and align reporting to UTC:

- DAU: unique users per day.
- MAU: unique users per calendar month, not the sum of DAU. A rolling 30-day unique-user metric can be configured separately.

These metrics represent installations/devices, not authenticated people across multiple devices.

During manual verification, confirm that activation reports, repeated interactions in one day do not create additional signals within the process, and the first interaction on the next UTC day reports. Check that idle/background days do not report and that payloads contain no repository or input content. Verify DAU/MAU on the real dashboard before marking dashboard acceptance complete. A successful build or a unit test does not establish actual ingestion.
