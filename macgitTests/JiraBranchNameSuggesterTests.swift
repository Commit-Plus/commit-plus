// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class JiraBranchNameSuggesterTests: XCTestCase {
    private func name(_ summary: String, key: String = "PROJ-123") -> String {
        JiraBranchNameSuggester.name(key: key, summary: summary)
    }

    func testKeyAndSlug() {
        XCTAssertEqual(name("Fix login crash"), "PROJ-123-fix-login-crash")
    }

    func testPunctuationCollapsesToSingleHyphens() {
        XCTAssertEqual(name("  [iOS] Fix: login -- crash (again)!  "), "PROJ-123-ios-fix-login-crash-again")
    }

    func testDiacriticsAreFoldedToASCII() {
        XCTAssertEqual(name("Sửa lỗi đăng nhập"), "PROJ-123-sua-loi-dang-nhap")
        XCTAssertEqual(name("Crème brûlée façade"), "PROJ-123-creme-brulee-facade")
    }

    func testEmojiAndSymbolsAreDropped() {
        XCTAssertEqual(name("🚀 Launch 🎉 page"), "PROJ-123-launch-page")
    }

    func testEmptyOrSymbolOnlySummaryKeepsKey() {
        XCTAssertEqual(name(""), "PROJ-123")
        XCTAssertEqual(name("🔥!!"), "PROJ-123")
    }

    func testLongSummaryIsCutAtHyphenAndKeepsKey() {
        let result = name("Refactor the repository synchronization pipeline to support incremental background refreshes")
        XCTAssertLessThanOrEqual(result.count, JiraBranchNameSuggester.maxLength)
        XCTAssertTrue(result.hasPrefix("PROJ-123-refactor-the-repository"))
        XCTAssertFalse(result.hasSuffix("-"))
        XCTAssertTrue("Refactor the repository synchronization pipeline to support incremental background refreshes"
            .lowercased().replacingOccurrences(of: " ", with: "-")
            .hasPrefix(String(result.dropFirst("PROJ-123-".count))), "must end on a whole word")
    }

    func testSingleVeryLongWordFallsBackToKey() {
        XCTAssertEqual(name(String(repeating: "a", count: 80)), "PROJ-123")
    }

    func testBugsSuggestBugfixAndOtherTypesSuggestFeature() {
        XCTAssertEqual(JiraBranchTarget.suggested(forIssueType: "Bug", gitFlowEnabled: true), .gitFlow(.bugfix))
        XCTAssertEqual(JiraBranchTarget.suggested(forIssueType: "Defect", gitFlowEnabled: true), .gitFlow(.bugfix))
        XCTAssertEqual(JiraBranchTarget.suggested(forIssueType: "Story", gitFlowEnabled: true), .gitFlow(.feature))
        XCTAssertEqual(JiraBranchTarget.suggested(forIssueType: "Task", gitFlowEnabled: true), .gitFlow(.feature))
    }

    func testWithoutGitFlowOnlyPlainBranchIsOffered() {
        XCTAssertEqual(JiraBranchTarget.suggested(forIssueType: "Bug", gitFlowEnabled: false), .plainBranch)
        XCTAssertEqual(JiraBranchTarget.options(gitFlowEnabled: false), [.plainBranch])
    }

    func testGitFlowOptionsExcludeReleaseAndKeepPlainBranch() {
        let options = JiraBranchTarget.options(gitFlowEnabled: true)
        XCTAssertEqual(options, [.gitFlow(.feature), .gitFlow(.bugfix), .gitFlow(.hotfix), .plainBranch])
        XCTAssertEqual(options.map(\.title), ["Start Feature…", "Start Bugfix…", "Start Hotfix…", "New Branch…"])
    }

    func testSuggestionSurvivesBranchSanitizerUnchanged() {
        for summary in ["Fix login crash", "Sửa lỗi đăng nhập", "a..b @{x} ~^:?*[\\ end.lock"] {
            let suggested = name(summary)
            XCTAssertEqual(GitBranchNameSanitizer.sanitize(suggested), suggested, summary)
        }
    }
}
