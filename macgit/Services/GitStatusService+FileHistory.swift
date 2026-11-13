// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// One commit that touched a file, with the path the file had at that commit.
nonisolated struct FileHistoryEntry: Identifiable, Equatable, Sendable {
    let commit: Commit
    let path: String
    let oldPath: String?
    let status: CommitFileStatus
    var id: String { commit.hash }

    var change: CommitFileChange { CommitFileChange(path: path, status: status, oldPath: oldPath) }
}

nonisolated struct FileBlameLine: Identifiable, Equatable, Sendable {
    let lineNumber: Int
    let hash: String
    let text: String
    var id: Int { lineNumber }
}

nonisolated struct FileBlameCommit: Equatable, Sendable {
    let hash: String
    let author: String
    let email: String
    let date: Date
    let summary: String
    var shortHash: String { String(hash.prefix(7)) }
}

nonisolated struct FileBlame: Equatable, Sendable {
    let lines: [FileBlameLine]
    let commits: [String: FileBlameCommit]
}

extension GitStatusService {
    nonisolated static let fileHistoryLimit = 1_000
    nonisolated static let fileBlameByteLimit = 16_000_000

    /// Commits that changed `path`, newest first, starting at `revision` and following renames.
    func fileHistory(path: String, revision: String, in repositoryURL: URL) async throws -> [FileHistoryEntry] {
        let data = try await runGitRaw(arguments: [
            "log", "--follow", "--no-notes", "-z", "--name-status", "--find-renames",
            "--format=%x01%H%x1f%P%x1f%s%x1f%an%x1f%ae%x1f%ad%x1f%D%x02", "--date=iso-strict",
            "--max-count=\(Self.fileHistoryLimit)", revision, "--", path
        ], in: repositoryURL, environment: ProcessInfo.processInfo.environment, outputByteLimit: 16_000_000)
        try Task.checkCancellation()
        return Self.parseFileHistory(data, path: path)
    }

    nonisolated static func parseFileHistory(_ data: Data, path: String) -> [FileHistoryEntry] {
        let formatter = ISO8601DateFormatter()
        var currentPath = path
        var entries: [FileHistoryEntry] = []
        for record in data.split(separator: 1) {
            guard let headerEnd = record.firstIndex(of: 2) else { continue }
            let header = String(decoding: record[..<headerEnd], as: UTF8.self)
                .split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard header.count >= 6, !header[0].isEmpty else { continue }
            let refs = header.count > 6
                ? header[6].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            let commit = Commit(hash: header[0], parents: header[1].split(separator: " ").map(String.init),
                message: header[2], author: header[3], email: header[4],
                date: formatter.date(from: header[5]) ?? Date(), refs: refs)
            // With -z the name-status fields are NUL separated: status, path[, new path].
            let fields = record[record.index(after: headerEnd)...].split(separator: 0)
                .map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .newlines) }
                .filter { !$0.isEmpty }
            var status = CommitFileStatus.modified
            var entryPath = currentPath
            var oldPath: String?
            if let code = fields.first {
                status = CommitFileStatus(rawValue: String(code.prefix(1))) ?? .modified
                if (code.hasPrefix("R") || code.hasPrefix("C")), fields.count >= 3 {
                    oldPath = fields[1]
                    entryPath = fields[2]
                } else if fields.count >= 2 {
                    entryPath = fields[1]
                }
            }
            entries.append(FileHistoryEntry(commit: commit, path: entryPath, oldPath: oldPath, status: status))
            currentPath = oldPath ?? entryPath
        }
        return entries
    }

    func fileBlame(path: String, revision: String, in repositoryURL: URL) async throws -> FileBlame {
        let data = try await runGitRaw(arguments: ["blame", "--porcelain", revision, "--", path],
            in: repositoryURL, environment: ProcessInfo.processInfo.environment,
            outputByteLimit: Self.fileBlameByteLimit)
        try Task.checkCancellation()
        guard !data.contains(0) else {
            throw GitError.commandFailed("Blame is unavailable for binary files.")
        }
        return try Self.parseFileBlame(data)
    }

    nonisolated static func parseFileBlame(_ data: Data) throws -> FileBlame {
        var lines: [FileBlameLine] = []
        var commits: [String: FileBlameCommit] = [:]
        var hash = ""
        var lineNumber = 0
        var fields: [String: String] = [:]
        for (index, raw) in data.split(separator: 10, omittingEmptySubsequences: false).enumerated() {
            if index.isMultiple(of: 512) { try Task.checkCancellation() }
            if raw.first == 9 {
                if commits[hash] == nil {
                    let email = (fields["author-mail"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                    commits[hash] = FileBlameCommit(hash: hash, author: fields["author"] ?? "",
                        email: email,
                        date: Date(timeIntervalSince1970: TimeInterval(fields["author-time"] ?? "") ?? 0),
                        summary: fields["summary"] ?? "")
                }
                fields = [:]
                lines.append(FileBlameLine(lineNumber: lineNumber, hash: hash,
                    text: String(decoding: raw.dropFirst(), as: UTF8.self)))
                continue
            }
            let line = String(decoding: raw, as: UTF8.self)
            guard let space = line.firstIndex(of: " ") else { continue }
            let key = String(line[..<space])
            let value = String(line[line.index(after: space)...])
            if [40, 64].contains(key.count), key.allSatisfy(\.isHexDigit) {
                hash = key
                let numbers = value.split(separator: " ")
                lineNumber = numbers.count >= 2 ? Int(numbers[1]) ?? lines.count + 1 : lines.count + 1
            } else {
                fields[key] = value
            }
        }
        return FileBlame(lines: lines, commits: commits)
    }
}
