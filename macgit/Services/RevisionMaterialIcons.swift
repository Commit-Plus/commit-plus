// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct RevisionMaterialIcons: Decodable, Sendable {
    let fileNames: [String: String]
    let fileExtensions: [String: String]
    let file: String
    let folder: String
    let folderExpanded: String
    let light: Overrides

    struct Overrides: Decodable, Sendable {
        let fileNames: [String: String]?
        let fileExtensions: [String: String]?
        let file: String?
    }

    static let shared: Self? = {
        guard let url = Bundle.main.url(forResource: "RevisionMaterialIconMappings", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()

    func icon(for path: String, isDirectory: Bool, isExpanded: Bool, isLight: Bool) -> String {
        let name = String(path.split(separator: "/").last ?? "").lowercased()
        if isDirectory {
            return isExpanded ? folderExpanded : folder
        }
        if let exact = (isLight ? light.fileNames?[name] : nil) ?? fileNames[name] { return exact }
        // Prefer compound extensions such as d.ts and test.js before ts or js.
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 1 {
            for index in 1..<parts.count {
                let suffix = parts[index...].joined(separator: ".")
                if let match = (isLight ? light.fileExtensions?[suffix] : nil) ?? fileExtensions[suffix] { return match }
            }
        }
        return (isLight ? light.file : nil) ?? file
    }
}
