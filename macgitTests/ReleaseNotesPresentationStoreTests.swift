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

import XCTest
@testable import macgit

@MainActor
final class ReleaseNotesPresentationStoreTests: XCTestCase {
    func testClaimsEachVersionOnlyOnce() async {
        let defaults = makeDefaults()
        let firstStore = makeStore(defaults: defaults, version: "1.2.0")

        let firstPresentation = await firstStore.claimPresentation()
        XCTAssertEqual(
            firstPresentation,
            ReleaseNotesPresentation(version: "1.2.0", markdown: "# Changelog")
        )
        let repeatedPresentation = await firstStore.claimPresentation()
        XCTAssertNil(repeatedPresentation)

        let nextVersionStore = makeStore(defaults: defaults, version: "1.2.1")
        let nextPresentation = await nextVersionStore.claimPresentation()
        XCTAssertEqual(nextPresentation?.version, "1.2.1")
    }

    func testFailedDownloadDoesNotConsumeVersion() async {
        let defaults = makeDefaults()
        let failedDownloadStore = ReleaseNotesPresentationStore(
            defaults: defaults,
            versionProvider: { "1.2.0" },
            changelogURLProvider: { URL(string: "https://example.com/CHANGELOG.md") },
            markdownLoader: { _ in throw URLError(.notConnectedToInternet) }
        )

        let failedPresentation = await failedDownloadStore.claimPresentation()
        XCTAssertNil(failedPresentation)
        let retriedPresentation = await makeStore(defaults: defaults, version: "1.2.0").claimPresentation()
        XCTAssertNotNil(retriedPresentation)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ReleaseNotesPresentationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(defaults: UserDefaults, version: String) -> ReleaseNotesPresentationStore {
        ReleaseNotesPresentationStore(
            defaults: defaults,
            versionProvider: { version },
            changelogURLProvider: { URL(string: "https://example.com/CHANGELOG.md") },
            markdownLoader: { _ in "# Changelog" }
        )
    }
}
