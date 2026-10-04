// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum CustomActionArgumentParserError: LocalizedError, Equatable {
    case unterminatedQuote
    case trailingEscape

    var errorDescription: String? {
        switch self {
        case .unterminatedQuote: "Arguments contain an unterminated quote."
        case .trailingEscape: "Arguments end with an incomplete escape."
        }
    }
}

enum CustomActionArgumentParser {
    private enum Quote {
        case single
        case double
    }

    static func parse(_ value: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Quote?
        var isEscaping = false
        var hasToken = false

        for character in value {
            if isEscaping {
                if quote == .double, !"$`\"\\\n".contains(character) { current.append("\\") }
                if character != "\n" { current.append(character) }
                isEscaping = false
                hasToken = true
                continue
            }

            if character == "\\", quote != .single {
                isEscaping = true
                hasToken = true
                continue
            }

            switch (quote, character) {
            case (.single, "'"):
                quote = nil
            case (.double, "\""):
                quote = nil
            case (nil, "'"):
                quote = .single
                hasToken = true
            case (nil, "\""):
                quote = .double
                hasToken = true
            case (nil, let character) where character.isWhitespace:
                if hasToken {
                    arguments.append(current)
                    current = ""
                    hasToken = false
                }
            default:
                current.append(character)
                hasToken = true
            }
        }

        if isEscaping { throw CustomActionArgumentParserError.trailingEscape }
        if quote != nil { throw CustomActionArgumentParserError.unterminatedQuote }
        if hasToken { arguments.append(current) }
        return arguments
    }

    static func joined(_ arguments: [String]) -> String {
        arguments.map { argument in
            guard argument.isEmpty || argument.contains(where: { $0.isWhitespace || "'\"\\".contains($0) }) else {
                return argument
            }
            return "\"" + argument
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }.joined(separator: " ")
    }
}

enum CustomActionValidationError: LocalizedError, Equatable {
    case emptyName
    case missingExecutable
    case executableNotAbsolute
    case executableUnavailable
    case missingScriptLanguage
    case missingScriptSource
    case scriptTooLarge
    case missingAvailability
    case unsupportedPlaceholder(String)
    case embeddedPlaceholder(String)

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter an action name."
        case .missingExecutable: "Choose an executable or script."
        case .executableNotAbsolute: "Executable paths must be absolute."
        case .executableUnavailable: "The executable or script is not available on this Mac."
        case .missingScriptLanguage: "Choose the script language."
        case .missingScriptSource: "The synced script is empty."
        case .scriptTooLarge: "Synced scripts must be no larger than 256 KB."
        case .missingAvailability: "Choose at least one availability context."
        case .unsupportedPlaceholder(let value): "Unsupported placeholder: \(value)."
        case .embeddedPlaceholder(let value): "\(value) must be a standalone argument."
        }
    }
}

enum CustomActionValidator {
    static let maximumScriptBytes = 256 * 1024
    private static let supportedPlaceholders: Set<String> = ["$REPO", "$FILE", "$SHA"]

    static func validate(_ action: CustomActionDefinition, fileManager: FileManager = .default) throws {
        guard !action.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CustomActionValidationError.emptyName
        }
        guard !action.availability.isEmpty else {
            throw CustomActionValidationError.missingAvailability
        }

        switch action.sourceKind {
        case .executable, .localScript:
            guard !action.executablePath.isEmpty else { throw CustomActionValidationError.missingExecutable }
            guard action.executablePath.hasPrefix("/") else { throw CustomActionValidationError.executableNotAbsolute }
            guard fileManager.fileExists(atPath: action.executablePath) else {
                throw CustomActionValidationError.executableUnavailable
            }
            if action.sourceKind == .executable,
               !fileManager.isExecutableFile(atPath: action.executablePath) {
                throw CustomActionValidationError.executableUnavailable
            }
            if action.sourceKind == .localScript, action.scriptLanguage == nil {
                throw CustomActionValidationError.missingScriptLanguage
            }
        case .syncedScript:
            guard action.scriptLanguage != nil else { throw CustomActionValidationError.missingScriptLanguage }
            guard let source = action.scriptSource, !source.isEmpty else {
                throw CustomActionValidationError.missingScriptSource
            }
            guard source.utf8.count <= maximumScriptBytes else {
                throw CustomActionValidationError.scriptTooLarge
            }
        }

        for argument in action.arguments {
            for index in argument.indices where argument[index] == "$" {
                let suffix = argument[index...]
                for placeholder in Self.supportedPlaceholders where suffix.hasPrefix(placeholder) {
                    let remainder = suffix.dropFirst(placeholder.count)
                    if let next = remainder.first, next.isLetter || next.isNumber || next == "_" {
                        continue
                    }
                    if argument != placeholder {
                        throw CustomActionValidationError.embeddedPlaceholder(placeholder)
                    }
                }
            }
        }
    }

    static func unavailableReason(
        for action: CustomActionDefinition,
        surface: CustomActionInvocationSurface,
        context: CustomActionInvocationContext,
        isTrusted: Bool
    ) -> String? {
        guard action.isEnabled else { return "This action is disabled." }
        guard action.availability.contains(surface.availability) else {
            return "This action is not available in this context."
        }
        guard isTrusted else { return "Review and trust this action on this Mac before running it." }
        if action.arguments.contains("$FILE"), context.filePaths.isEmpty {
            return "Select one or more files first."
        }
        if action.arguments.contains("$SHA"), context.commitHashes.isEmpty {
            return "Select one or more commits first."
        }
        return nil
    }
}

enum CustomActionArgumentExpander {
    static func expand(
        _ arguments: [String],
        context: CustomActionInvocationContext
    ) -> [String] {
        arguments.flatMap { argument in
            switch argument {
            case "$REPO": [context.repositoryURL.path]
            case "$FILE": context.filePaths
            case "$SHA": context.commitHashes
            default: [argument]
            }
        }
    }
}
