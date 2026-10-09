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
            ReleaseNotesPresentation(version: "1.2.0", markdown: "Release description")
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
            releaseLoader: { _ in throw URLError(.notConnectedToInternet) }
        )

        let failedPresentation = await failedDownloadStore.claimPresentation()
        XCTAssertNil(failedPresentation)
        let retriedPresentation = await makeStore(defaults: defaults, version: "1.2.0").claimPresentation()
        XCTAssertNotNil(retriedPresentation)
    }

    func testExplicitViewingRemainsAvailableAfterStartupPresentation() async {
        let store = makeStore(defaults: makeDefaults(), version: "1.1.12")
        let initial = await store.claimPresentation()
        let repeatedAutomatic = await store.claimPresentation()
        let explicit = await store.loadPresentation()

        XCTAssertNotNil(initial)
        XCTAssertNil(repeatedAutomatic)
        XCTAssertEqual(explicit, initial)
    }

    func testDifferentReleaseNotesDoNotConsumeInstalledVersion() async {
        for remoteVersion in ["1.1.12", "1.1.9"] {
            let defaults = makeDefaults()
            let store = ReleaseNotesPresentationStore(
                defaults: defaults,
                versionProvider: { "1.1.10" },
                releaseLoader: { _ in self.releaseData(tag: "v\(remoteVersion)") }
            )

            let presentation = await store.claimPresentation()
            XCTAssertNil(presentation)
            let matchingPresentation = await makeStore(defaults: defaults, version: "1.1.10")
                .claimPresentation()
            XCTAssertNotNil(matchingPresentation)
        }
    }

    func testEmptyReleaseDescriptionIsNotPresented() async {
        let store = ReleaseNotesPresentationStore(
            defaults: makeDefaults(),
            versionProvider: { "1.1.10" },
            releaseLoader: { _ in self.releaseData(tag: "v1.1.10", body: " \n") }
        )

        let presentation = await store.claimPresentation()
        XCTAssertNil(presentation)
    }

    private func releaseData(tag: String, body: String = "Release description") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "body": body, "draft": false
        ])
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
            releaseLoader: { url in
                XCTAssertEqual(
                    url.absoluteString,
                    "https://api.github.com/repos/Commit-Plus/commit-plus/releases/tags/v\(version)"
                )
                return self.releaseData(tag: "v\(version)")
            }
        )
    }
}
