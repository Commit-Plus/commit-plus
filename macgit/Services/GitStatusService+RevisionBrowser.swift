// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Foundation
import CryptoKit

extension GitStatusService: RevisionBrowserServing {
    nonisolated static let revisionPreviewByteLimit = 2_000_000

    func browserSnapshot(revision: String, in repositoryURL: URL) async throws -> RevisionBrowserSnapshot {
        let sha = try await resolveComparisonRef(revision, branchesOnly: false, in: repositoryURL)
        let subject = try await runGit(arguments: ["show", "-s", "--format=%s", "--no-notes", sha, "--"], in: repositoryURL)
        let changesData = try await runGitRaw(arguments: [
            "show", "--name-status", "-z", "--first-parent", "--root", "--format=",
            "--find-renames", "--no-ext-diff", "--no-textconv", sha, "--"
        ], in: repositoryURL, environment: ProcessInfo.processInfo.environment, outputByteLimit: 8_000_000)
        let changes = try Self.parseComparisonFiles(changesData)
        try Task.checkCancellation()
        // Include the old path so surviving ancestors of deletions/renames are marked too.
        return RevisionBrowserSnapshot(commitID: sha, subject: subject.trimmingCharacters(in: .newlines),
            changedPaths: changes.flatMap { [$0.path, $0.oldPath].compactMap { $0 } })
    }

    func browserEntries(treeID: String, parentPath: String, in repositoryURL: URL) async throws -> [RevisionTreeEntry] {
        try Self.validateBrowserObjectID(treeID)
        let data = try await runGitRaw(arguments: ["ls-tree", "-z", "-l", "--full-tree", treeID],
            in: repositoryURL, environment: ProcessInfo.processInfo.environment, outputByteLimit: 8_000_000)
        return try Self.parseBrowserEntries(data, parentPath: parentPath)
    }

    nonisolated static func validateBrowserObjectID(_ id: String) throws {
        guard [40, 64].contains(id.count), id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw GitError.commandFailed("Invalid Git object ID.")
        }
    }

    nonisolated static func parseBrowserEntries(_ data: Data, parentPath: String) throws -> [RevisionTreeEntry] {
        guard data.isEmpty || data.last == 0 else { throw GitError.commandFailed("Incomplete repository tree.") }
        var entries: [RevisionTreeEntry] = []
        for record in data.split(separator: 0) {
            try Task.checkCancellation()
            guard entries.count < 20_000, let tab = record.firstIndex(of: 9),
                  let name = String(data: record[record.index(after: tab)...], encoding: .utf8),
                  !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                throw GitError.commandFailed("This folder is too large or contains an unsupported filename.")
            }
            let fields = String(decoding: record[..<tab], as: UTF8.self).split(separator: " ")
            guard fields.count == 4 else { throw GitError.commandFailed("Invalid repository tree entry.") }
            let oid = String(fields[2])
            try validateBrowserObjectID(oid)
            let size = Int(fields[3])
            guard ["tree", "blob", "commit"].contains(fields[1]),
                  fields[3] == "-" || (size != nil && size! >= 0) else {
                throw GitError.commandFailed("Invalid repository object metadata.")
            }
            entries.append(RevisionTreeEntry(path: parentPath.isEmpty ? name : parentPath + "/" + name,
                objectID: oid, mode: String(fields[0]), objectType: String(fields[1]), size: size))
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.path < $1.path
        }
    }

    func browserPreview(entry: RevisionTreeEntry, in repositoryURL: URL) async throws -> RevisionFilePreview {
        try Self.validateBrowserObjectID(entry.objectID)
        if entry.isSubmodule { return .notice("Submodule commit: \(entry.objectID)") }
        guard entry.objectType == "blob" else { return .notice("Select a file to preview its contents.") }
        guard let size = entry.size, size <= Self.revisionPreviewByteLimit else {
            return .notice("File exceeds the 2 MB preview limit.")
        }
        let data = try await runGitRaw(arguments: ["cat-file", "blob", entry.objectID], in: repositoryURL,
            environment: ProcessInfo.processInfo.environment, outputByteLimit: Self.revisionPreviewByteLimit)
        try Task.checkCancellation()
        if !entry.isSymlink, let text = String(data: data, encoding: .utf8), let pointer = GitLFSPointer(text) {
            if pointer.size > Self.revisionPreviewByteLimit {
                return .notice("Git LFS content: \(pointer.size) bytes\nSHA-256: \(pointer.oid)\nContent exceeds the 2 MB preview limit. Use Git LFS to download the current checkout.")
            }
            if let cached = try await cachedLFSData(pointer, in: repositoryURL) {
                return try Self.decodeBrowserPreview(cached, isSymlink: false)
            }
            return RevisionFilePreview(text: text, lines: [], message: "Git LFS content is not available in the local cache.\nSize: \(pointer.size) bytes\nSHA-256: \(pointer.oid)", lfsPointer: pointer)
        }
        return try Self.decodeBrowserPreview(data, isSymlink: entry.isSymlink)
    }

    private func cachedLFSData(_ pointer: GitLFSPointer, in repository: URL) async throws -> Data? {
        guard let environment = try? await runLFS(["env"], in: repository),
              let line = environment.split(separator: "\n").first(where: { $0.hasPrefix("LocalMediaDir=") }) else { return nil }
        let root = URL(fileURLWithPath: String(line.dropFirst("LocalMediaDir=".count)))
        let url = root.appendingPathComponent(String(pointer.oid.prefix(2)))
            .appendingPathComponent(String(pointer.oid.dropFirst(2).prefix(2))).appendingPathComponent(pointer.oid)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.revisionPreviewByteLimit + 1) ?? Data()
        guard data.count == pointer.size else { return nil }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return hash == pointer.oid ? data : nil
    }

    nonisolated static func decodeBrowserPreview(_ data: Data, isSymlink: Bool) throws -> RevisionFilePreview {
        if !isSymlink, NSImage(data: data) != nil {
            return RevisionFilePreview(text: nil, lines: [], message: nil, imageData: data)
        }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            return .notice("Binary file or unsupported text encoding. UTF-8 preview is unavailable.")
        }
        if isSymlink { return RevisionFilePreview(text: text, lines: [], message: "Symbolic link target: \(text)") }
        if let pointer = GitLFSPointer(text) {
            return RevisionFilePreview(text: text, lines: [], message: "Git LFS pointer · \(pointer.size) bytes\nSHA-256: \(pointer.oid)", lfsPointer: pointer)
        }
        let rawLines = text.components(separatedBy: "\n")
        guard rawLines.count <= 50_000, rawLines.allSatisfy({ $0.utf8.count <= 16_000 }) else {
            return RevisionFilePreview(text: text, lines: [], message: "Text exceeds the line count or line length preview limit. You can still copy its contents.")
        }
        var lines: [DiffLine] = []
        for (index, line) in rawLines.enumerated() {
            try Task.checkCancellation()
            lines.append(DiffLine(oldLineNumber: nil, newLineNumber: index + 1, text: line, type: .context))
        }
        return RevisionFilePreview(text: text, lines: text.isEmpty ? [] : lines, message: text.isEmpty ? "Empty file" : nil)
    }
}
