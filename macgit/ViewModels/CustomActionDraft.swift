// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct CustomActionDraft {
    var id: UUID
    var name: String
    var sourceKind: CustomActionSourceKind
    var executablePath: String
    var scriptLanguage: CustomActionScriptLanguage
    var scriptSource: String
    var sourceFileName: String
    var rawArguments: String
    var repositoryAvailable: Bool
    var filesAvailable: Bool
    var commitsAvailable: Bool
    var isEnabled: Bool
    var alwaysShowOutput: Bool
    var sortIndex: Int

    init(action: CustomActionDefinition? = nil) {
        id = action?.id ?? UUID()
        name = action?.name ?? ""
        sourceKind = action?.sourceKind ?? .executable
        executablePath = action?.executablePath ?? ""
        scriptLanguage = action?.scriptLanguage ?? .sh
        scriptSource = action?.scriptSource ?? ""
        sourceFileName = action?.sourceFileName ?? "script.sh"
        rawArguments = CustomActionArgumentParser.joined(action?.arguments ?? [])
        repositoryAvailable = action?.availability.contains(.repository) ?? true
        filesAvailable = action?.availability.contains(.selectedFiles) ?? false
        commitsAvailable = action?.availability.contains(.selectedCommits) ?? false
        isEnabled = action?.isEnabled ?? true
        alwaysShowOutput = action?.alwaysShowOutput ?? false
        sortIndex = action?.sortIndex ?? 0
    }

    func definition() throws -> CustomActionDefinition {
        var availability: CustomActionAvailability = []
        if repositoryAvailable { availability.insert(.repository) }
        if filesAvailable { availability.insert(.selectedFiles) }
        if commitsAvailable { availability.insert(.selectedCommits) }
        let action = CustomActionDefinition(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceKind: sourceKind,
            executablePath: executablePath,
            scriptLanguage: sourceKind == .executable ? nil : scriptLanguage,
            scriptSource: sourceKind == .syncedScript ? scriptSource : nil,
            sourceFileName: sourceKind == .syncedScript ? sourceFileName : nil,
            arguments: try CustomActionArgumentParser.parse(rawArguments),
            availability: availability,
            isEnabled: isEnabled,
            alwaysShowOutput: alwaysShowOutput,
            sortIndex: sortIndex
        )
        try CustomActionValidator.validate(action)
        return action
    }
}
