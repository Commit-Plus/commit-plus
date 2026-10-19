// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class RepositoryReadmeHTMLTests: XCTestCase {
    func testReadmeKeepsPermissivePolicy() {
        let html = RepositoryReadmeHTML.render("<img src=\"https://example.com/a.png\">")

        XCTAssertTrue(html.contains("img-src 'self' https: http: data:"))
        XCTAssertTrue(html.contains("style-src 'unsafe-inline'"))
    }

    func testPullRequestContentRestrictsStylesAndImageHosts() {
        let html = RepositoryReadmeHTML.render(
            "<div style=\"position:fixed\">x</div><script>alert(1)</script>",
            untrustedContentHost: "github.com"
        )

        XCTAssertTrue(html.contains("img-src https://github.com https://*.github.com https://*.githubusercontent.com data:"))
        XCTAssertFalse(html.contains("'unsafe-inline'"))
        XCTAssertFalse(html.contains("<script>"))
        guard let nonceRange = html.range(of: #"(?<=style-src 'nonce-)[^']+"#, options: .regularExpression) else {
            return XCTFail("Missing style nonce")
        }
        XCTAssertTrue(html.contains("<style nonce=\"\(html[nonceRange])\">"))
    }

    func testSelfHostedProviderImagesUseInstanceHost() {
        XCTAssertEqual(
            RepositoryReadmeHTML.imageSources(forProviderHost: "GitLab.Example.com"),
            "https://gitlab.example.com https://*.gitlab.example.com"
        )
        XCTAssertEqual(RepositoryReadmeHTML.imageSources(forProviderHost: ""), "")
    }
}
