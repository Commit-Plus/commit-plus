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

final class FeatureAccessNoticeTests: XCTestCase {
    func testProNoticeNamesTheBlockedFeature() {
        let notice = FeatureAccessNotice(feature: .pullRequests, denial: .requiresPro)

        XCTAssertEqual(notice.title, "Commit+ Pro Required")
        XCTAssertTrue(notice.message.contains("Pull Requests"))
    }

    func testSignedOutPrivateRepositoryNoticeRequestsSignIn() {
        let notice = FeatureAccessNotice(feature: .privateRepositories, denial: .requiresPro)

        XCTAssertEqual(notice.title(isSignedIn: false), "Sign In Required")
        XCTAssertEqual(
            notice.message(isSignedIn: false),
            "Sign in to Commit+ to use private repositories."
        )
    }

    func testSignedInPrivateRepositoryNoticeShowsAnnualizedProPrice() {
        let notice = FeatureAccessNotice(feature: .privateRepositories, denial: .requiresPro)

        XCTAssertEqual(notice.title(isSignedIn: true), "Commit+ Pro Required")
        XCTAssertEqual(
            notice.message(isSignedIn: true),
            "Upgrade to Commit+ Pro from $3.25/month (billed annually) to use private repositories."
        )
    }

    func testVisibilityNoticeExplainsRetryableFailure() {
        let notice = FeatureAccessNotice(
            feature: .privateRepositories,
            denial: .repositoryVisibilityUnavailable
        )

        XCTAssertEqual(notice.title, "Repository Access Unavailable")
        XCTAssertTrue(notice.message.contains("try again"))
    }

    func testJiraNoticeRequestsSignInOrUpgradeWithoutRepositoryWording() {
        let notice = FeatureAccessNotice(feature: .jiraIssues, denial: .requiresPro)

        XCTAssertEqual(notice.title(isSignedIn: false), "Sign In Required")
        XCTAssertEqual(notice.message(isSignedIn: false), "Sign in to Commit+ to use Jira Issues.")
        XCTAssertEqual(notice.title(isSignedIn: true), "Commit+ Pro Required")
        XCTAssertTrue(notice.message(isSignedIn: true).contains("Jira Issues"))
        XCTAssertFalse(notice.message(isSignedIn: true).contains("repository"))
    }

    func testDisabledNoticeDoesNotSuggestUpgrade() {
        let notice = FeatureAccessNotice(feature: .pullRequests, denial: .featureDisabled)

        XCTAssertEqual(notice.title, "Feature Unavailable")
        XCTAssertFalse(notice.message.contains("Pro"))
    }
}
