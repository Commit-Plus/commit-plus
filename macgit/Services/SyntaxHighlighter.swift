//
//  SyntaxHighlighter.swift
//  macgit
//

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
import Foundation
import SwiftUI

@MainActor
struct SyntaxHighlighter {
    typealias TokenType = SyntaxTokenizer.TokenType
    private let tokenizer: SyntaxTokenizer

    init(fileExtension: String) {
        tokenizer = SyntaxTokenizer(fileExtension: Self.syntaxIdentifier(forLanguage: fileExtension))
    }

    func attributedString(for text: String, fontSize: CGFloat = 12) -> AttributedString {
        var attributed = AttributedString(text)

        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        attributed.font = Font(baseFont)
        attributed.foregroundColor = .primary

        for (range, type) in tokenizer.tokenRanges(in: text) {
            if let swiftRange = Range(range, in: text),
               let attrRange = convertRange(swiftRange, in: attributed) {
                if let color = Self.tokenColor(for: type) {
                    attributed[attrRange].foregroundColor = Color(nsColor: color)
                }
            }
        }

        return attributed
    }

    func nsAttributedString(for text: String, fontSize: CGFloat = 12) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ]
        )

        for (range, type) in tokenizer.tokenRanges(in: text) {
            guard NSMaxRange(range) <= NSMaxRange(fullRange),
                  let color = Self.tokenColor(for: type) else {
                continue
            }
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }

        return attributed
    }

    static func tokenColor(for type: TokenType) -> NSColor? {
        switch type {
        case .keyword:
            NSColor(calibratedRed: 0.80, green: 0.35, blue: 0.60, alpha: 1.0)
        case .string:
            NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.20, alpha: 1.0)
        case .comment:
            NSColor(calibratedRed: 0.50, green: 0.50, blue: 0.50, alpha: 1.0)
        case .number:
            NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.75, alpha: 1.0)
        case .type:
            NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.70, alpha: 1.0)
        case .attribute:
            NSColor(calibratedRed: 0.65, green: 0.40, blue: 0.20, alpha: 1.0)
        case .normal:
            nil
        }
    }

    private func convertRange(_ range: Range<String.Index>, in attributed: AttributedString) -> Range<AttributedString.Index>? {
        guard let start = AttributedString.Index(range.lowerBound, within: attributed),
              let end = AttributedString.Index(range.upperBound, within: attributed) else {
            return nil
        }
        return start..<end
    }

    /// Code fences use language names while file views usually pass extensions.
    static func syntaxIdentifier(forLanguage language: String) -> String {
        let identifier = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return switch identifier {
        case "javascript", "node", "nodejs": "js"
        case "typescript": "ts"
        case "python": "py"
        case "shell", "console", "shellscript": "sh"
        case "objective-c", "objc": "m"
        case "objective-c++", "objc++": "mm"
        case "c++": "cpp"
        case "c#", "csharp": "cs"
        case "kotlin": "kt"
        case "rust": "rs"
        case "ruby": "rb"
        case "golang": "go"
        case "docker", "containerfile": "dockerfile"
        case "dotenv": "env"
        default: identifier
        }
    }

    /// Resolve filenames before passing the syntax identifier through diff rows.
    static func syntaxIdentifier(forFilePath path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if name == "dockerfile" || name.hasPrefix("dockerfile.") ||
            name == "containerfile" || name.hasPrefix("containerfile.") {
            return "dockerfile"
        }
        if name == ".env" || name.hasPrefix(".env.") { return "env" }
        if ["makefile", "gnumakefile"].contains(name) { return "makefile" }
        if ["gemfile", "rakefile"].contains(name) { return "rb" }
        if [".bashrc", ".zshrc", ".bash_profile", ".profile"].contains(name) { return "sh" }
        return URL(fileURLWithPath: name).pathExtension
    }


}
