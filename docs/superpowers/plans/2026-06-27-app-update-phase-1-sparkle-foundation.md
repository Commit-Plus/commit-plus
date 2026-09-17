# Direct App Update Phase 1: Sparkle Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Sparkle 2, create a testable app-wide updater adapter and `AppUpdateController`, and run one silent update metadata check on every launch plus a manual `Check for Updates...` menu action.

**Architecture:** Add Sparkle through Swift Package Manager, configure generated Info.plist keys in the project file, and hide updater behavior behind `AppUpdaterProtocol`. `macgitApp` owns one `AppUpdateController` instance, injects it into the SwiftUI environment, starts it after launch, and exposes the manual menu command. Tests use a fake updater that records calls and drives controller state changes without importing Sparkle.

**Tech Stack:** Swift 6, SwiftUI, Sparkle 2, XCTest, `xcodebuild`, Xcode project build settings with generated Info.plist entries.

**Design spec:** [docs/superpowers/specs/2026-06-27-app-update-design.md](../specs/2026-06-27-app-update-design.md)

---

## Prerequisite

Start from a clean isolated worktree on branch `codex/app-update-phase-1-sparkle-foundation`.

## File Structure

- Create `macgit/Services/AppUpdateState.swift`: shared sidebar/app-update enum.
- Create `macgit/Services/AppUpdaterProtocol.swift`: abstraction used by the controller and tests.
- Create `macgit/Services/AppUpdateController.swift`: main-actor app-wide observable object.
- Create `macgit/Services/SparkleAppUpdater.swift`: Sparkle-backed adapter and delegate bridge.
- Modify `macgit/App/macgitApp.swift`: own the controller, inject it, start background checks, add menu item.
- Modify `macgit.xcodeproj/project.pbxproj`: add Sparkle package/product and generated Info.plist keys.
- Create `macgitTests/AppUpdateControllerTests.swift`: fake-based controller tests.

## Task 1: Add Failing Controller Tests

**Files:**
- Create: `macgitTests/AppUpdateControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `macgitTests/AppUpdateControllerTests.swift`:

```swift
import XCTest
@testable import macgit

@MainActor
final class AppUpdateControllerTests: XCTestCase {
    func testStartPerformsSilentBackgroundCheckOnce() async {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        controller.start()

        XCTAssertEqual(updater.startCallCount, 1)
        XCTAssertEqual(updater.backgroundCheckCallCount, 1)
        XCTAssertEqual(controller.state, .checking)
    }

    func testAvailableUpdateTransitionsToAvailableState() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        updater.emit(.updateAvailable)

        XCTAssertEqual(controller.state, .available)
    }

    func testUserInitiatedDownloadTransitionsToDownloadingState() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        updater.emit(.updateAvailable)
        updater.emit(.downloadStarted)

        XCTAssertEqual(controller.state, .downloading)
    }

    func testOpenUpdateWindowDelegatesToUpdater() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.openUpdateWindow()

        XCTAssertEqual(updater.showUpdateWindowCallCount, 1)
    }

    func testManualCheckDelegatesToUpdater() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.checkForUpdates()

        XCTAssertEqual(updater.userInitiatedCheckCallCount, 1)
    }
}

@MainActor
private final class FakeAppUpdater: AppUpdaterProtocol {
    var startCallCount = 0
    var backgroundCheckCallCount = 0
    var showUpdateWindowCallCount = 0
    var userInitiatedCheckCallCount = 0
    var eventHandler: ((AppUpdaterEvent) -> Void)?

    func start() {
        startCallCount += 1
    }

    func checkForUpdatesInBackground() {
        backgroundCheckCallCount += 1
    }

    func showUpdateWindow() {
        showUpdateWindowCallCount += 1
    }

    func checkForUpdates() {
        userInitiatedCheckCallCount += 1
    }

    func setEventHandler(_ handler: @escaping (AppUpdaterEvent) -> Void) {
        eventHandler = handler
    }

    func emit(_ event: AppUpdaterEvent) {
        eventHandler?(event)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/AppUpdateControllerTests test
```

Expected: build fails because `AppUpdateController`, `AppUpdaterProtocol`, and `AppUpdateState` do not exist yet.

## Task 2: Add Minimal Controller Types

**Files:**
- Create: `macgit/Services/AppUpdateState.swift`
- Create: `macgit/Services/AppUpdaterProtocol.swift`
- Create: `macgit/Services/AppUpdateController.swift`

- [ ] **Step 3: Create `AppUpdateState`**

Create `macgit/Services/AppUpdateState.swift`:

```swift
import Foundation

enum AppUpdateState: Equatable {
    case idle
    case checking
    case available
    case downloading
}
```

- [ ] **Step 4: Create `AppUpdaterProtocol`**

Create `macgit/Services/AppUpdaterProtocol.swift`:

```swift
import Foundation

enum AppUpdaterEvent {
    case updateAvailable
    case noUpdateFound
    case downloadStarted
    case sessionDismissed
}

@MainActor
protocol AppUpdaterProtocol: AnyObject {
    func start()
    func checkForUpdatesInBackground()
    func showUpdateWindow()
    func checkForUpdates()
    func setEventHandler(_ handler: @escaping (AppUpdaterEvent) -> Void)
}
```

- [ ] **Step 5: Create the minimal controller**

Create `macgit/Services/AppUpdateController.swift`:

```swift
import Foundation

@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var state: AppUpdateState = .idle

    private let updater: AppUpdaterProtocol
    private var hasStarted = false

    init(updater: AppUpdaterProtocol) {
        self.updater = updater
        updater.setEventHandler { [weak self] event in
            self?.handle(event)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updater.start()
        state = .checking
        updater.checkForUpdatesInBackground()
    }

    func openUpdateWindow() {
        updater.showUpdateWindow()
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    private func handle(_ event: AppUpdaterEvent) {
        switch event {
        case .updateAvailable:
            state = .available
        case .noUpdateFound:
            state = .idle
        case .downloadStarted:
            state = .downloading
        case .sessionDismissed:
            if state != .downloading {
                state = .available
            }
        }
    }
}
```

- [ ] **Step 6: Add a regression test for session dismissal returning to the available state**

Append to `macgitTests/AppUpdateControllerTests.swift`:

```swift
    func testDismissedSessionKeepsAvailableState() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        updater.emit(.updateAvailable)
        updater.emit(.sessionDismissed)

        XCTAssertEqual(controller.state, .available)
    }
```

- [ ] **Step 7: Run the controller tests and verify green**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/AppUpdateControllerTests test
```

Expected: `** TEST SUCCEEDED **`

## Task 3: Add Sparkle Adapter And App Wiring

**Files:**
- Create: `macgit/Services/SparkleAppUpdater.swift`
- Modify: `macgit/App/macgitApp.swift`
- Modify: `macgit.xcodeproj/project.pbxproj`

- [ ] **Step 8: Add Sparkle package and generated Info.plist keys**

Modify `macgit.xcodeproj/project.pbxproj` to add the Sparkle package and the generated Info.plist entries on the `macgit` target:

```pbxproj
packageReferences = (
    /* Sparkle package reference */
);
packageProductDependencies = (
    /* Sparkle */
);
INFOPLIST_KEY_SUFeedURL = "https://commit-plus.github.io/commit-plus/appcast.xml";
INFOPLIST_KEY_SUPublicEDKey = "$(SPARKLE_PUBLIC_ED_KEY)";
INFOPLIST_KEY_SUAutomaticallyUpdate = NO;
INFOPLIST_KEY_SUEnableAutomaticChecks = YES;
INFOPLIST_KEY_SUAllowsAutomaticUpdates = NO;
```

Also add a build setting placeholder so local builds compile without secrets in the repo:

```pbxproj
SPARKLE_PUBLIC_ED_KEY = "";
```

- [ ] **Step 9: Create the Sparkle-backed updater**

Create `macgit/Services/SparkleAppUpdater.swift`:

```swift
import Foundation
import Sparkle

@MainActor
final class SparkleAppUpdater: NSObject, AppUpdaterProtocol {
    private let updaterController: SPUStandardUpdaterController
    private var eventHandler: ((AppUpdaterEvent) -> Void)?

    override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        updaterController.updater.delegate = self
    }

    func start() {
        try? updaterController.startUpdater()
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
        eventHandler?(.noUpdateFound)
    }

    func showUpdateWindow() {
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setEventHandler(_ handler: @escaping (AppUpdaterEvent) -> Void) {
        eventHandler = handler
    }
}

extension SparkleAppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        eventHandler?(.updateAvailable)
    }

    func updater(_ updater: SPUUpdater, userDidMakeChoice userChoice: SPUUserUpdateChoice, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if userChoice == .install {
            eventHandler?(.downloadStarted)
        } else {
            eventHandler?(.sessionDismissed)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        eventHandler?(.noUpdateFound)
    }
}
```

- [ ] **Step 10: Wire the controller into the app**

Modify `macgit/App/macgitApp.swift`:

```swift
@main
struct macgitApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var appUpdateController = AppUpdateController(updater: SparkleAppUpdater())

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appUpdateController)
                .task {
                    appUpdateController.start()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdateController.checkForUpdates()
                }
            }

            // existing command groups stay here
        }
    }
}
```

- [ ] **Step 11: Build and fix compile errors**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: initial errors are limited to Sparkle API mismatches or package wiring issues. Fix those directly in `SparkleAppUpdater.swift` and `project.pbxproj` before moving on.

## Task 4: Finalize Phase 1 Verification

**Files:**
- Modify: `macgit/Services/AppUpdateController.swift`
- Modify: `macgit/Services/SparkleAppUpdater.swift`
- Modify: `macgitTests/AppUpdateControllerTests.swift`

- [ ] **Step 12: Remove the placeholder “no update” emission from the adapter and move silent-idle transitions into explicit delegate callbacks**

Update `SparkleAppUpdater.swift` so `checkForUpdatesInBackground()` only starts the check:

```swift
    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }
```

Keep `eventHandler?(.noUpdateFound)` only in the real “no update” callback you confirm compiles against the installed Sparkle version.

- [ ] **Step 13: Add one more regression test for the no-update path**

Append to `macgitTests/AppUpdateControllerTests.swift`:

```swift
    func testNoUpdateFoundReturnsToIdle() {
        let updater = FakeAppUpdater()
        let controller = AppUpdateController(updater: updater)

        controller.start()
        updater.emit(.noUpdateFound)

        XCTAssertEqual(controller.state, .idle)
    }
```

- [ ] **Step 14: Run the focused test target**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/AppUpdateControllerTests test
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 15: Run the full project tests**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 16: Commit the phase work**

Run:

```bash
git add macgit/App/macgitApp.swift macgit/Services/AppUpdateState.swift macgit/Services/AppUpdaterProtocol.swift macgit/Services/AppUpdateController.swift macgit/Services/SparkleAppUpdater.swift macgitTests/AppUpdateControllerTests.swift macgit.xcodeproj/project.pbxproj docs/superpowers/plans/2026-06-27-app-update-roadmap.md
git commit -m "feat: add app update foundation"
```

Expected: a clean commit on `codex/app-update-phase-1-sparkle-foundation`.
