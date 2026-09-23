// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import XCTest
@testable import macgit

final class SyntaxHighlighterTests: XCTestCase {
    @MainActor
    func testFilenameDetection() {
        let cases = [
            "build/Dockerfile": "dockerfile", "Dockerfile.dev": "dockerfile",
            "Containerfile": "dockerfile", "app.dockerfile": "dockerfile",
            ".env.local": "env", "config/.env": "env", "Makefile": "makefile",
            "Gemfile": "rb", ".zshrc": "sh", "src/FILE.TSX": "tsx",
            "README.md": "md", "unknown.txt": "txt",
        ]
        for (path, expected) in cases {
            XCTAssertEqual(SyntaxHighlighter.syntaxIdentifier(forFilePath: path), expected, path)
        }
    }

    @MainActor
    func testPopularLanguageKeywordsAndFileFormats() {
        let cases: [(String, String, String)] = [
            ("swift", "guard ready else { return }", "guard"),
            ("js", "const value = true", "const"), ("ts", "interface Item {}", "interface"),
            ("py", "def hello():", "def"), ("c", "typedef int Count;", "typedef"),
            ("cpp", "template<typename T>", "template"), ("go", "chan int", "chan"),
            ("rs", "impl Item {}", "impl"), ("java", "public class Item {}", "public"),
            ("kt", "fun hello() {}", "fun"), ("cs", "using System;", "using"),
            ("dart", "factory Item() {}", "factory"), ("rb", "require 'json'", "require"),
            ("php", "echo $value;", "echo"), ("sh", "fi", "fi"),
            ("md", "# Heading", "# Heading"), ("dockerfile", "FROM alpine", "FROM"),
            ("yml", "enabled: true", "enabled"), ("sql", "select * from users", "select"),
            ("json", "{\"enabled\": true}", "\"enabled\""),
            ("html", "<div class=\"box\">", "<div"), ("xml", "<item id=\"1\"/>", "<item"),
            ("css", "color: #fff;", "color"), ("toml", "[package]", "[package]"),
            ("ini", "enabled=true", "enabled"), ("env", "PORT=3000", "PORT"),
            ("makefile", "include common.mk", "include"),
        ]
        for (ext, source, token) in cases {
            let result = SyntaxHighlighter(fileExtension: ext).nsAttributedString(for: source)
            let index = (source as NSString).range(of: token).location
            XCTAssertNotEqual(result.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor,
                              NSColor.textColor, ext)
            XCTAssertEqual(result.string, source)
        }
    }

    @MainActor
    func testStringsProtectCommentMarkersAndEscapedQuotes() {
        let source = #"let url = "https://example.com/\"name\"" // comment "quote""#
        let result = SyntaxHighlighter(fileExtension: "swift").nsAttributedString(for: source)
        func color(_ token: String) -> NSColor? {
            result.attribute(.foregroundColor, at: (source as NSString).range(of: token).location,
                             effectiveRange: nil) as? NSColor
        }
        XCTAssertEqual(color("https"), color("example"))
        XCTAssertEqual(color("https"), color("name"))
        XCTAssertEqual(color("comment"), color("quote"))
        XCTAssertNotEqual(color("https"), color("comment"))
    }

    @MainActor
    func testUnicodeAndJSONKeyPrecedence() {
        let source = "{\"tên😀\": \"giá trị😀\", \"enabled\": true}"
        let result = SyntaxHighlighter(fileExtension: "json").nsAttributedString(for: source)
        func color(_ token: String) -> NSColor? {
            result.attribute(.foregroundColor, at: (source as NSString).range(of: token).location,
                             effectiveRange: nil) as? NSColor
        }
        XCTAssertNotEqual(color("tên"), color("giá"))
        XCTAssertNotEqual(color("enabled"), color("true"))
        XCTAssertEqual(String(SyntaxHighlighter(fileExtension: "json").attributedString(for: source).characters), source)
    }
}
