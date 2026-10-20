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
import AppKit
import Foundation

enum SearchFileOpenError: LocalizedError {
    case fileNotFound(String)
    case applicationNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File no longer exists: \(path)"
        case .applicationNotFound(let name):
            return "Could not find \(name) to open this file."
        }
    }
}

struct SearchFileApplication: Identifiable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL

    var id: String { bundleIdentifier }
}

private struct SearchFileApplicationCandidate {
    let bundleIdentifier: String
    let displayName: String
}

enum SearchFileApplicationResolver {
    static let previewBundleIdentifier = "com.apple.Preview"

    private static let candidates = [
        SearchFileApplicationCandidate(bundleIdentifier: "com.microsoft.VSCode", displayName: "Visual Studio Code"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.microsoft.VSCodeInsiders", displayName: "Visual Studio Code Insiders"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.jetbrains.intellij", displayName: "IntelliJ IDEA"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.jetbrains.intellij.ce", displayName: "IntelliJ IDEA Community Edition"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.jetbrains.WebStorm", displayName: "WebStorm"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.jetbrains.pycharm", displayName: "PyCharm"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.jetbrains.CLion", displayName: "CLion"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.google.android.studio", displayName: "Android Studio"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.todesktop.230313mzl4w4u92", displayName: "Cursor"),
        SearchFileApplicationCandidate(bundleIdentifier: "dev.zed.Zed", displayName: "Zed"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.sublimetext.4", displayName: "Sublime Text"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.apple.dt.Xcode", displayName: "Xcode"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.panic.Nova", displayName: "Nova"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.barebones.bbedit", displayName: "BBEdit"),
        SearchFileApplicationCandidate(bundleIdentifier: "com.macromates.TextMate", displayName: "TextMate"),
        SearchFileApplicationCandidate(bundleIdentifier: previewBundleIdentifier, displayName: "Preview")
    ]

    static func availableApplications(
        applicationURL: (String) -> URL?
    ) -> [SearchFileApplication] {
        candidates.compactMap { candidate in
            guard let url = applicationURL(candidate.bundleIdentifier) else { return nil }
            return SearchFileApplication(
                bundleIdentifier: candidate.bundleIdentifier,
                displayName: candidate.displayName,
                applicationURL: url
            )
        }
    }

    @MainActor
    static func availableApplications(workspace: NSWorkspace = .shared) -> [SearchFileApplication] {
        availableApplications { workspace.urlForApplication(withBundleIdentifier: $0) }
    }
}

/// Where an editor should place the cursor when opening a working-tree file.
nonisolated enum SearchFileLineTarget: Equatable, Sendable {
    /// The first change in the working-tree file compared with HEAD.
    case workingTreeChange
    /// The first line a commit changed, used only while the working-tree file still matches that commit.
    case commitChange(String)
}

enum SearchFileOpener {
    @MainActor
    static func open(
        relativePath: String,
        lineTarget: SearchFileLineTarget? = nil,
        in repositoryURL: URL,
        using application: SearchFileApplication,
        workspace: NSWorkspace = .shared
    ) async throws {
        let fileURL = repositoryURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SearchFileOpenError.fileNotFound(relativePath)
        }

        guard FileManager.default.fileExists(atPath: application.applicationURL.path) else {
            throw SearchFileOpenError.applicationNotFound(application.displayName)
        }

        if let lineTarget,
           let command = editorCommand(application: application, fileURL: fileURL) {
            let lineNumber = await GitStatusService.shared.editorLineNumber(
                for: relativePath,
                target: lineTarget,
                in: repositoryURL
            )
            try Task.checkCancellation()
            // Fall back to a plain open when the line is unknown or the editor CLI fails.
            if let lineNumber, await run(command(lineNumber)) {
                return
            }
        }
        try Task.checkCancellation()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.open(
                [fileURL],
                withApplicationAt: application.applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private struct EditorCommand {
        let executableURL: URL
        let arguments: [String]
    }

    private static func run(_ command: EditorCommand) async -> Bool {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
    }

    /// Returns a builder for the editor's command-line tool, or nil when the editor has no supported CLI.
    private static func editorCommand(
        application: SearchFileApplication,
        fileURL: URL
    ) -> ((Int) -> EditorCommand)? {
        let path = fileURL.path
        // An explicit column keeps a path that ends in ":<digits>" from being read as a position.
        let position: (Int) -> String = { "\(path):\($0):1" }
        let relativeExecutable: String
        let arguments: (Int) -> [String]
        switch application.bundleIdentifier {
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92":
            relativeExecutable = switch application.bundleIdentifier {
            case "com.microsoft.VSCodeInsiders": "Contents/Resources/app/bin/code-insiders"
            case "com.todesktop.230313mzl4w4u92": "Contents/Resources/app/bin/cursor"
            default: "Contents/Resources/app/bin/code"
            }
            arguments = { ["--reuse-window", "--goto", position($0)] }
        case "dev.zed.Zed":
            relativeExecutable = "Contents/MacOS/cli"
            arguments = { [position($0)] }
        case "com.sublimetext.4":
            relativeExecutable = "Contents/SharedSupport/bin/subl"
            arguments = { [position($0)] }
        case "com.apple.dt.Xcode":
            relativeExecutable = "Contents/Developer/usr/bin/xed"
            arguments = { ["--line", String($0), path] }
        case "com.barebones.bbedit":
            relativeExecutable = "Contents/Helpers/bbedit_tool"
            arguments = { ["+\($0)", path] }
        case "com.macromates.TextMate":
            relativeExecutable = "Contents/MacOS/mate"
            arguments = { ["--line", String($0), path] }
        default:
            return nil
        }

        let executableURL = application.applicationURL.appendingPathComponent(relativeExecutable)
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { return nil }
        return { EditorCommand(executableURL: executableURL, arguments: arguments($0)) }
    }
}
