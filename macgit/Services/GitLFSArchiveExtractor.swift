// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSArchiveExtractor: GitRuntimeExtracting {
    nonisolated static func validateListing(_ listing: String) throws {
        let entries = listing.split(separator: "\n")
        guard !entries.isEmpty, entries.allSatisfy({ entry in
            !entry.hasPrefix("/") && !entry.split(separator: "/").contains("..")
                && entry.hasPrefix("git-lfs-3.8.0/")
        }) else { throw GitError.commandFailed("The Git LFS archive contains unsafe paths.") }
    }

    func extract(archiveURL: URL, to destinationURL: URL) throws {
        let listing = try runTar(["-tf", archiveURL.path])
        try Self.validateListing(listing)
        let details = try runTar(["-tvf", archiveURL.path])
        guard details.split(separator: "\n").allSatisfy({ $0.hasPrefix("-") || $0.hasPrefix("d") }) else {
            throw GitError.commandFailed("The Git LFS archive contains unsupported links.")
        }
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        _ = try runTar(["-xf", archiveURL.path, "-C", destinationURL.path])
    }

    private func runTar(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GitError.commandFailed("Could not unpack Git LFS.") }
        return String(decoding: data, as: UTF8.self)
    }
}
