// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class JiraSiteNormalizerTests: XCTestCase {
    func testBareNameExpandsToAtlassianSite() throws {
        XCTAssertEqual(try JiraSiteNormalizer.normalize("acme"), URL(string: "https://acme.atlassian.net"))
        XCTAssertEqual(try JiraSiteNormalizer.normalize("  Acme-Team \n"), URL(string: "https://acme-team.atlassian.net"))
    }

    func testHostAndURLFormsReduceToSiteRoot() throws {
        let expected = URL(string: "https://acme.atlassian.net")
        XCTAssertEqual(try JiraSiteNormalizer.normalize("acme.atlassian.net"), expected)
        XCTAssertEqual(try JiraSiteNormalizer.normalize("https://ACME.atlassian.net/jira/software/projects"), expected)
        XCTAssertEqual(try JiraSiteNormalizer.normalize("https://acme.atlassian.net:443/"), expected)
    }

    func testRejectsNonCloudOrUnsafeSites() {
        for input in [
            "",
            "http://acme.atlassian.net",
            "https://jira.example.com",
            "https://acme.atlassian.net.evil.com",
            "https://evilatlassian.net",
            "https://a.b.atlassian.net",
            "https://user:pass@acme.atlassian.net",
            "https://acme.atlassian.net:8443",
            "ftp://acme.atlassian.net",
            "äcme",
        ] {
            XCTAssertThrowsError(try JiraSiteNormalizer.normalize(input), input) { error in
                XCTAssertEqual(error as? JiraError, .unsupportedSite, input)
            }
        }
    }
}
