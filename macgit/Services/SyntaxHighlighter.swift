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
    enum TokenType {
        case keyword
        case string
        case comment
        case number
        case type
        case attribute
        case normal
    }

    struct TokenRules {
        let regex: NSRegularExpression
        let groups: [(name: String, type: TokenType)]
    }

    private static let keywordPattern: String = {
        let commonKeywords = Array(Set([
            "func", "var", "let", "if", "else", "for", "while", "return", "import", "class", "struct", "enum",
            "protocol", "extension", "init", "switch", "case", "default", "break", "continue", "in",
            "where", "typealias", "operator", "throws", "throw", "try", "catch", "do", "guard", "defer",
            "self", "Self", "super", "static", "final", "override", "open", "public", "internal", "private",
            "fileprivate", "weak", "inout", "await", "async", "actor", "some", "any", "macro",
            "const", "goto", "typedef", "union", "extern", "auto", "register", "volatile", "sizeof", "inline", "restrict",
            "function", "interface", "extends", "implements", "new", "this", "typeof", "instanceof", "of", "yield", "export", "from",
            "package", "namespace", "module", "protected", "abstract", "synchronized", "finally",
            "def", "elif", "as", "with", "except", "raise", "assert", "lambda",
            "nonlocal", "global", "pass", "del", "and", "or", "not", "is", "True", "False",
            "None", "match", "print", "println", "mut", "fn",
            "impl", "trait", "pub", "use", "mod", "crate", "unsafe",
            "move", "loop", "delete", "void"
        ]))
        return commonKeywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    }()

    private static var rulesCache: [String: TokenRules] = [:]

    private let rules: TokenRules?
    private let fileExtension: String

    init(fileExtension: String) {
        self.fileExtension = Self.syntaxIdentifier(forLanguage: fileExtension)
        self.rules = SyntaxHighlighter.rules(for: self.fileExtension)
    }

    func attributedString(for text: String, fontSize: CGFloat = 12) -> AttributedString {
        var attributed = AttributedString(text)

        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        attributed.font = Font(baseFont)
        attributed.foregroundColor = .primary

        for (range, type) in mergedTokenRanges(in: text) {
            if let swiftRange = Range(range, in: text),
               let attrRange = convertRange(swiftRange, in: attributed) {
                if let color = tokenColor(for: type) {
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

        for (range, type) in mergedTokenRanges(in: text) {
            guard NSMaxRange(range) <= NSMaxRange(fullRange),
                  let color = tokenColor(for: type) else {
                continue
            }
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }

        return attributed
    }

    private func mergedTokenRanges(in text: String) -> [(NSRange, TokenType)] {
        guard let rules else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var tokens: [(NSRange, TokenType)] = []
        // One combined expression consumes strings/comments atomically, without
        // rescanning the entire remaining line once for every individual token.
        rules.regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            for group in rules.groups where match.range(withName: group.name).location != NSNotFound {
                tokens.append((match.range, group.type))
                break
            }
        }
        return tokens
    }

    private func tokenColor(for type: TokenType) -> NSColor? {
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

    private static func rules(for ext: String) -> TokenRules? {
        if let cached = rulesCache[ext] { return cached }

        let strings: [(String, TokenType)] = [
            (#""(?:[^"\\]|\\.)*""#, .string),
            (#"'(?:[^'\\]|\\.)*'"#, .string),
        ]
        let cComments: [(String, TokenType)] = [
            (#"//[^\n]*"#, .comment), (#"/\*[\s\S]*?\*/"#, .comment),
        ]
        let hashComments: [(String, TokenType)] = [(#"#[^\n]*"#, .comment)]
        let numbers: [(String, TokenType)] = [
            (#"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#, .number),
        ]
        let types: [(String, TokenType)] = [(#"\b[A-Z][A-Za-z0-9_]*\b"#, .type)]
        let attributes: [(String, TokenType)] = [(#"@\w+"#, .attribute)]
        func keywords(_ words: String) -> [(String, TokenType)] {
            [(#"\b(?:"# + words.split(separator: " ").joined(separator: "|") + #")\b"#, .keyword)]
        }
        let common = [("\\b(?:\(keywordPattern)|true|false|null|nil)\\b", TokenType.keyword)]
        var patterns: [(String, TokenType)]

        switch ext {
        case "swift":
            patterns = cComments + strings + attributes + common + types + numbers
        case "js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx":
            patterns = cComments + strings + [(#"`(?:[^`\\]|\\.)*`"#, .string)]
                + common + keywords("boolean number string undefined null keyof infer readonly declare satisfies")
                + types + numbers
        case "py", "pyw", "pyi":
            patterns = hashComments + [
                (#"\"\"\"[\s\S]*?\"\"\""#, .string), (#"'''[\s\S]*?'''"#, .string),
            ] + strings + attributes + common + numbers
        case "c", "cpp", "cc", "cxx", "h", "hpp", "hh", "hxx", "m", "mm":
            patterns = cComments + strings + [(#"#\s*\w+"#, .attribute)] + common
                + keywords("int char float double bool short long signed unsigned template typename constexpr nullptr virtual friend")
                + types + numbers
        case "go":
            patterns = cComments + strings + [(#"`[^`]*`"#, .string)] + common
                + keywords("chan defer fallthrough go map range select type int string bool") + types + numbers
        case "rs":
            patterns = cComments + strings + [(#"#\!?\[[^\]]*\]"#, .attribute)] + common
                + keywords("dyn ref enum unsafe async where bool str usize i32 u32") + types + numbers
        case "java", "kt", "kts", "cs", "dart":
            patterns = cComments + strings + attributes + common
                + keywords("val fun object when data sealed suspend companion constructor boolean int double bool string using get set record event delegate lock params out ref is as dynamic required late factory mixin")
                + types + numbers
        case "rb", "rake", "gemspec":
            patterns = hashComments + strings + common
                + keywords("end unless until then elsif begin rescue ensure require include attr_reader attr_accessor puts yield") + types + numbers
        case "php", "phtml":
            patterns = cComments + hashComments + strings + [(#"\$[A-Za-z_]\w*"#, .attribute)]
                + common + keywords("echo require require_once include include_once foreach endif endfor endforeach null") + types + numbers
        case "sh", "bash", "zsh":
            patterns = hashComments + strings + [(#"\$\{[^}]*\}|\$[A-Za-z_]\w*"#, .attribute)]
                + common + keywords("then fi done esac elif until echo local export source function") + numbers
        case "json", "jsonc", "json5":
            patterns = (ext == "json" ? [] : cComments)
                + [(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, .attribute)]
                + strings + keywords("true false null") + numbers
        case "yaml", "yml":
            patterns = hashComments + [(#"[\w.-]+(?=\s*:(?:\s|$))"#, .attribute)]
                + strings + [(#"[&*][\w.-]+|![!\w!:/.-]+"#, .type)]
                + keywords("true false null yes no on off") + numbers
        case "sql":
            patterns = [(#"--[^\n]*|/\*[\s\S]*?\*/"#, .comment)]
                + [(#"'(?:[^']|'')*'"#, .string)] + strings
                + [(#"(?i)\b(?:select|insert|update|delete|from|where|join|left|right|inner|outer|on|group|by|order|having|limit|offset|union|all|distinct|create|table|index|drop|alter|add|column|values|set|and|or|not|null|is|in|between|like|exists|case|when|then|else|end|as|with|recursive|returning|into|using|natural|cross|full|fetch|for|of|nowait|skip|locked|share|key|primary|foreign|references|constraint|check|default|unique|view|trigger|procedure|function|database|schema|transaction|commit|rollback|savepoint|release|grant|revoke|privileges|to|identified|password|account|lock|unlock|if|cascade|restrict|true|false)\b"#, .keyword)] + numbers
        case "md", "markdown", "mdx":
            patterns = [
                (#"<!--[\s\S]*?-->"#, .comment),
                (#"(?m)^\s{0,3}#{1,6}\s+.*$"#, .keyword),
                (#"`+[^`]*`+|(?m)^\s*`{3,}.*$|^\s*~{3,}.*$"#, .string),
                (#"!?\[[^\]]*\]\([^)]*\)"#, .attribute),
                (#"\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|_[^_]+_"#, .type),
                (#"(?m)^\s*(?:[-+*>]|\d+\.)\s"#, .keyword),
            ]
        case "dockerfile", "docker":
            patterns = [(#"(?m)^\s*#[^\n]*"#, .comment)] + strings
                + [(#"(?im)^\s*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b"#, .keyword)]
                + [(#"\$\{[^}]*\}|\$[A-Za-z_]\w*|--[\w-]+"#, .attribute)] + numbers
        case "html", "htm", "xml", "xhtml", "plist":
            patterns = [(#"<!--[\s\S]*?-->"#, .comment)] + strings
                + [(#"</?[\w:.-]+|/?>"#, .keyword), (#"[\w:.-]+(?=\s*=)"#, .attribute)]
        case "css", "scss", "sass", "less":
            patterns = (ext == "css" ? Array(cComments.dropFirst()) : cComments) + strings
                + [(#"#[0-9a-fA-F]{3,8}\b"#, .number),
                   (#"--[\w-]+|[\w-]+(?=\s*:)"#, .attribute),
                   (#"[@$.#][A-Za-z_][\w-]*"#, .type),
                   (#"!important\b"#, .keyword)] + numbers
        case "toml", "ini", "cfg", "conf", "env", "properties":
            patterns = [(#"(?m)^\s*[#;][^\n]*"#, .comment)] + strings
                + [(#"(?m)^\s*\[.*?\]"#, .type), (#"[\w.-]+(?=\s*=)"#, .attribute)]
                + hashComments + keywords("true false") + numbers
        case "makefile", "mk":
            patterns = hashComments + strings
                + [(#"\$\([^)]+\)|\$[@<^?*]"#, .attribute), (#"^[\w./% -]+(?=:)"#, .type)]
                + keywords("include ifdef ifndef ifeq ifneq else endif export override define endef") + numbers
        default:
            patterns = cComments + hashComments + strings + common + types + numbers
        }

        let groups = patterns.enumerated().map { (name: "token\($0.offset)", type: $0.element.1) }
        let pattern = zip(patterns, groups).map { entry, group in
            "(?<\(group.name)>\(entry.0))"
        }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            assertionFailure("Invalid syntax highlighting pattern for \(ext)")
            return nil
        }
        let result = TokenRules(regex: regex, groups: groups)
        rulesCache[ext] = result
        return result
    }
}
