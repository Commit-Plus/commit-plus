// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest

@testable import macgit

final class SyntaxTokenizerTests: XCTestCase {
    func testStringsAndCommentsConsumeEmbeddedKeywords() {
        let text = #"let value = "class 123" // return 456"#
        let tokens = SyntaxTokenizer(fileExtension: "swift").tokenRanges(in: text)
        let strings = tokens.map { (text as NSString).substring(with: $0.0) }
        XCTAssertEqual(strings, ["let", #""class 123""#, "// return 456"])
        XCTAssertEqual(tokens.map(\.1), [.keyword, .string, .comment])
    }

    func testRangesAreUTF16AndRemainInsideUnicodeText() {
        let text = #"let emoji = "🧑🏽‍💻 tiếng Việt" // 中文"#
        let tokens = SyntaxTokenizer(fileExtension: "swift").tokenRanges(in: text)
        XCTAssertEqual(tokens.count, 3)
        for (range, _) in tokens {
            XCTAssertLessThanOrEqual(NSMaxRange(range), (text as NSString).length)
            XCTAssertNotNil(Range(range, in: text))
        }
        XCTAssertEqual((text as NSString).substring(with: tokens[1].0), #""🧑🏽‍💻 tiếng Việt""#)
    }

    func testTokenRulesCanBeSharedAcrossBackgroundWorkers() async {
        let text = "SELECT name FROM users WHERE id = 42"
        let expected = SyntaxTokenizer(fileExtension: "sql").tokenRanges(in: text)
        let results = await withTaskGroup(of: [NSRange].self) { group in
            for _ in 0..<100 {
                group.addTask {
                    SyntaxTokenizer(fileExtension: "sql").tokenRanges(in: text).map(\.0)
                }
            }
            var results: [[NSRange]] = []
            for await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(results.count, 100)
        for result in results { XCTAssertEqual(result, expected.map(\.0)) }
        XCTAssertEqual(expected.map(\.1), [.keyword, .keyword, .keyword, .number])
    }
}
