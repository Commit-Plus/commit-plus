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

final class GitProviderOAuthTests: XCTestCase {
    func testPKCEVerifierUsesAllowedCharacters() {
        let verifier = GitProviderPKCE.generateVerifier()
        let allowedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        )

        XCTAssertTrue((43...128).contains(verifier.count))
        XCTAssertNil(verifier.unicodeScalars.first { !allowedCharacters.contains($0) })
    }

    func testPKCEChallengeIsBase64URLWithoutPadding() {
        let challenge = GitProviderPKCE.challenge(
            for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        )

        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func testCallbackRejectsMismatchedState() throws {
        let session = try makeSession(state: "expected-state")
        let callbackURL = try XCTUnwrap(
            URL(string: "macgit://git-provider/oauth/callback?code=oauth-code&state=wrong-state")
        )

        XCTAssertThrowsError(try GitProviderOAuthCallback.parse(callbackURL, for: session)) { error in
            XCTAssertEqual(error as? GitProviderOAuthError, .stateMismatch)
        }
    }

    func testCallbackExtractsAuthorizationCode() throws {
        let session = try makeSession(state: "expected-state")
        let callbackURL = try XCTUnwrap(
            URL(string: "macgit://git-provider/oauth/callback?code=oauth-code&state=expected-state")
        )

        let callback = try GitProviderOAuthCallback.parse(callbackURL, for: session)

        XCTAssertEqual(callback, GitProviderOAuthCallback(code: "oauth-code", state: "expected-state"))
    }

    func testForwardedCallbackMatchesAppCallbackURL() throws {
        let session = try makeForwardedSession(state: "expected-state")
        let callbackURL = try XCTUnwrap(
            URL(string: "macgit://git-provider/oauth/github/callback?code=oauth-code&state=expected-state")
        )

        let callback = try GitProviderOAuthCallback.parse(callbackURL, for: session)

        XCTAssertEqual(callback.code, "oauth-code")
        XCTAssertEqual(session.redirectURI.scheme, "https")
    }

    func testForwardedCallbackRejectsProviderRedirectAndOtherPaths() throws {
        let session = try makeForwardedSession(state: "expected-state")
        for value in [
            "https://commitplus.app/oauth/github/callback?code=oauth-code&state=expected-state",
            "macgit://git-provider/oauth/callback?code=oauth-code&state=expected-state"
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertThrowsError(try GitProviderOAuthCallback.parse(url, for: session)) { error in
                XCTAssertEqual(error as? GitProviderOAuthError, .unsupportedCallback)
            }
        }
    }

    func testDeniedCallbackWithMatchingStateIsAccessDenied() throws {
        let session = try makeForwardedSession(state: "expected-state")
        let url = try XCTUnwrap(URL(
            string: "macgit://git-provider/oauth/github/callback?error=access_denied&state=expected-state"
        ))

        XCTAssertThrowsError(try GitProviderOAuthCallback.parse(url, for: session)) { error in
            XCTAssertEqual(error as? GitProviderOAuthError, .accessDenied)
        }
    }

    func testErrorCallbackIsCheckedAgainstStateFirst() throws {
        let session = try makeForwardedSession(state: "expected-state")
        let forged = try XCTUnwrap(URL(
            string: "macgit://git-provider/oauth/github/callback?error=access_denied&state=forged"
        ))
        let missing = try XCTUnwrap(URL(
            string: "macgit://git-provider/oauth/github/callback?error=access_denied"
        ))

        XCTAssertThrowsError(try GitProviderOAuthCallback.parse(forged, for: session)) { error in
            XCTAssertEqual(error as? GitProviderOAuthError, .stateMismatch)
        }
        XCTAssertThrowsError(try GitProviderOAuthCallback.parse(missing, for: session)) { error in
            XCTAssertEqual(error as? GitProviderOAuthError, .missingState)
        }
    }

    func testOtherProviderErrorUsesDescription() throws {
        let session = try makeForwardedSession(state: "expected-state")
        let url = try XCTUnwrap(URL(
            string: "macgit://git-provider/oauth/github/callback?error=server_error&error_description=Try%20later&state=expected-state"
        ))

        XCTAssertThrowsError(try GitProviderOAuthCallback.parse(url, for: session)) { error in
            XCTAssertEqual(error as? GitProviderOAuthError, .providerMessage("Try later"))
        }
    }

    private func makeForwardedSession(state: String) throws -> GitProviderOAuthSession {
        GitProviderOAuthSession(
            provider: .github,
            host: .githubDotCom,
            state: state,
            codeVerifier: "test-verifier",
            redirectURI: try XCTUnwrap(URL(string: "https://commitplus.app/oauth/github/callback")),
            appCallbackURL: try XCTUnwrap(URL(string: "macgit://git-provider/oauth/github/callback"))
        )
    }

    private func makeSession(state: String) throws -> GitProviderOAuthSession {
        GitProviderOAuthSession(
            provider: .github,
            host: .githubDotCom,
            state: state,
            codeVerifier: "test-verifier",
            redirectURI: try XCTUnwrap(URL(string: "macgit://git-provider/oauth/callback"))
        )
    }
}
