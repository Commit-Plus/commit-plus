// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import UniformTypeIdentifiers

nonisolated struct RevisionMaterialIcons: Decodable, Sendable {
    let fileNames: [String: String]
    let fileExtensions: [String: String]
    let file: String
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

    /// The Material icon for a file. Folders use `SystemFolderIcon` instead.
    func icon(for path: String, isLight: Bool) -> String {
        let name = String(path.split(separator: "/").last ?? "").lowercased()
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

/// The standard macOS (Finder) folder icon, used for every folder in file trees.
@MainActor
enum SystemFolderIcon {
    static let image: NSImage = NSWorkspace.shared.icon(for: .folder)
}
