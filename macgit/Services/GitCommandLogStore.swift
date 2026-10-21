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

actor GitCommandLogStore {
    static let shared = GitCommandLogStore()

    static var logsDirectoryURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Commit+", isDirectory: true)
    }

    static var logFileURL: URL {
        logsDirectoryURL.appendingPathComponent("git-commands.log")
    }

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let formatter: ISO8601DateFormatter

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        formatter = ISO8601DateFormatter()
    }

    func record(
        arguments: [String],
        directory: URL,
        duration: TimeInterval,
        error: Error?
    ) {
        guard userDefaults.bool(forKey: AdvancedSettingsStore.verboseGitLoggingKey) else {
            return
        }

        let status = error == nil ? "success" : "failure"
        let command = Self.sanitized(arguments: arguments)
            .map(Self.shellQuoted)
            .joined(separator: " ")
        let directoryPath = Self.abbreviatedHomePath(directory.path)
        let line = [
            formatter.string(from: Date()),
            "[\(status)]",
            String(format: "[%.3fs]", duration),
            "git \(command)",
            "(cwd: \(directoryPath))\n"
        ].joined(separator: " ")

        do {
            try fileManager.createDirectory(
                at: Self.logsDirectoryURL,
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: Self.logFileURL.path) {
                fileManager.createFile(atPath: Self.logFileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: Self.logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // Diagnostics must never interfere with Git operations.
        }
    }

    static func sanitized(arguments: [String]) -> [String] {
        var result: [String] = []
        var redactNext = false

        for argument in arguments {
            if redactNext {
                result.append("<redacted>")
                redactNext = false
                continue
            }

            let lowercased = argument.lowercased()
            if ["--password", "--token", "--oauth-token", "--access-token"].contains(lowercased) {
                result.append(argument)
                redactNext = true
            } else if lowercased.contains("authorization:")
                        || lowercased.contains("http.extraheader")
                        || lowercased.contains("password=")
                        || lowercased.contains("token=") {
                result.append("<redacted>")
            } else {
                result.append(sanitizedURL(argument))
            }
        }
        return result
    }

    private static func sanitizedURL(_ value: String) -> String {
        guard var components = URLComponents(string: value),
              components.user != nil || components.password != nil else {
            return value
        }
        components.user = "<redacted>"
        components.password = nil
        return components.string ?? "<redacted-url>"
    }

    static func shellQuoted(_ value: String) -> String {
        guard value.contains(where: \.isWhitespace) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func abbreviatedHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
