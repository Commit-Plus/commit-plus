// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation

struct CustomActionAvailability: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let repository = Self(rawValue: 1 << 0)
    static let selectedFiles = Self(rawValue: 1 << 1)
    static let selectedCommits = Self(rawValue: 1 << 2)
}

enum CustomActionSourceKind: String, Codable, CaseIterable, Sendable {
    case executable
    case localScript
    case syncedScript
}

enum CustomActionScriptLanguage: String, Codable, CaseIterable, Sendable {
    case sh
    case bash
    case zsh
    case python

    var displayName: String {
        switch self {
        case .sh: "Shell"
        case .bash: "Bash"
        case .zsh: "Zsh"
        case .python: "Python"
        }
    }

    static func inferred(from url: URL) -> Self? {
        switch url.pathExtension.lowercased() {
        case "sh": .sh
        case "bash": .bash
        case "zsh": .zsh
        case "py": .python
        default: nil
        }
    }
}

struct CustomActionDefinition: Codable, Identifiable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1

    var id: UUID
    var name: String
    var sourceKind: CustomActionSourceKind
    var executablePath: String
    var scriptLanguage: CustomActionScriptLanguage?
    var scriptSource: String?
    var sourceFileName: String?
    var arguments: [String]
    var availability: CustomActionAvailability
    var isEnabled: Bool
    var alwaysShowOutput: Bool
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        name: String,
        sourceKind: CustomActionSourceKind = .executable,
        executablePath: String,
        scriptLanguage: CustomActionScriptLanguage? = nil,
        scriptSource: String? = nil,
        sourceFileName: String? = nil,
        arguments: [String] = [],
        availability: CustomActionAvailability = [.repository],
        isEnabled: Bool = true,
        alwaysShowOutput: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.sourceKind = sourceKind
        self.executablePath = executablePath
        self.scriptLanguage = scriptLanguage
        self.scriptSource = scriptSource
        self.sourceFileName = sourceFileName
        self.arguments = arguments
        self.availability = availability
        self.isEnabled = isEnabled
        self.alwaysShowOutput = alwaysShowOutput
        self.sortIndex = sortIndex
    }

    var trustFingerprint: String {
        let payload = [
            sourceKind.rawValue,
            executablePath,
            scriptLanguage?.rawValue ?? "",
            scriptSource ?? "",
            arguments.joined(separator: "\u{0}"),
        ].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var duplicated: Self {
        var copy = self
        copy.id = UUID()
        copy.name = "\(name) Copy"
        return copy
    }
}

struct CustomActionInvocationContext: Equatable, Sendable {
    let repositoryURL: URL
    var filePaths: [String]
    var commitHashes: [String]
}

enum CustomActionInvocationSurface: Sendable {
    case repository
    case selectedFiles
    case selectedCommits

    var availability: CustomActionAvailability {
        switch self {
        case .repository: .repository
        case .selectedFiles: .selectedFiles
        case .selectedCommits: .selectedCommits
        }
    }
}
