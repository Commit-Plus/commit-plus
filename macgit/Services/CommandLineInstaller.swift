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

struct CommandLineInstaller {
    let directory: URL
    let executable: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin"),
         executable: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/commit")) {
        self.directory = directory
        self.executable = executable
    }

    var destination: URL { directory.appendingPathComponent("commit") }

    var installedCommand: URL? {
        guard let target = symbolicLinkTarget,
              FileManager.default.isExecutableFile(atPath: target.path),
              target.standardizedFileURL == executable.standardizedFileURL || isCommitPlusHelper(target) else {
            return nil
        }
        return destination
    }

    var isInstalled: Bool {
        installedCommand != nil
    }

    var conflict: String? {
        let manager = FileManager.default
        if (try? manager.attributesOfItem(atPath: destination.path)) != nil, !isInstalled {
            return "A different file or command already exists at \(destination.path). Move it before installing."
        }
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("commit")
            if candidate.standardizedFileURL != destination.standardizedFileURL,
               manager.isExecutableFile(atPath: candidate.path) {
                return "Another commit command exists at \(candidate.path). Resolve the name conflict before installing."
            }
        }
        return nil
    }

    func install() throws {
        if isInstalled { return }
        if let conflict { throw RepositoryOpenError.message(conflict) }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RepositoryOpenError.message("The command is missing from this app bundle. Reinstall Commit+.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Exclusive creation: never replace a file, command, or symlink that appeared in the meantime.
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: executable)
    }

    private var symbolicLinkTarget: URL? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path) else {
            return nil
        }
        if target.hasPrefix("/") {
            return URL(fileURLWithPath: target).standardizedFileURL
        }
        return directory.appendingPathComponent(target).standardizedFileURL
    }

    private func isCommitPlusHelper(_ target: URL) -> Bool {
        let helpersDirectory = target.deletingLastPathComponent()
        let contentsDirectory = helpersDirectory.deletingLastPathComponent()
        let application = contentsDirectory.deletingLastPathComponent()
        return target.lastPathComponent == "commit"
            && helpersDirectory.lastPathComponent == "Helpers"
            && contentsDirectory.lastPathComponent == "Contents"
            && application.lastPathComponent == "Commit+.app"
    }
}
