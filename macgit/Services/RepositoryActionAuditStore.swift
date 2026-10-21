// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SQLite3

nonisolated enum RepositoryActionAuditOrigin: String, Sendable {
    case user
    case system

    var label: String {
        switch self {
        case .user: "User"
        case .system: "System"
        }
    }
}

nonisolated enum RepositoryActionAuditStatus: String, Sendable {
    case succeeded
    case failed
    case cancelled
}

nonisolated struct RepositoryActionAuditRecord: Sendable {
    let repositoryPath: String
    let title: String
    let origin: RepositoryActionAuditOrigin
    let command: String
    let output: String
    let status: RepositoryActionAuditStatus
    let finishedAt: Date
    let duration: TimeInterval
}

nonisolated struct RepositoryActionAuditSummary: Identifiable, Equatable, Sendable {
    let id: Int64
    let title: String
    let origin: RepositoryActionAuditOrigin
    let summary: String
    let status: RepositoryActionAuditStatus
    let finishedAt: Date
}

nonisolated struct RepositoryActionAuditEntry: Identifiable, Equatable, Sendable {
    let id: Int64
    let title: String
    let origin: RepositoryActionAuditOrigin
    let command: String
    let summary: String
    let output: String
    let isOutputTruncated: Bool
    let status: RepositoryActionAuditStatus
    let finishedAt: Date
    let duration: TimeInterval
}

extension Notification.Name {
    /// Posted after an audit record is stored; `userInfo["repositoryPath"]` names its repository.
    static let repositoryActionAuditDidRecord = Notification.Name("macgit.repositoryActionAuditDidRecord")
}

/// Decides which Git commands are audited and how they are titled and redacted.
nonisolated enum RepositoryActionAudit {
    /// Automatic work wraps its Git calls in `$origin.withValue(.system)`.
    @TaskLocal static var origin: RepositoryActionAuditOrigin = .user

    static let outputByteLimit = 64 * 1024
    static let summaryCharacterLimit = 140

    private static let optionsWithValue: Set<String> = [
        "-m", "-F", "--message", "--file", "--author", "--date", "-X", "--strategy",
        "--strategy-option", "--onto", "--depth", "--deepen", "--shallow-since",
        "--shallow-exclude", "--format", "-o", "--push-option", "--repo", "--upload-pack",
        "--receive-pack", "--exec", "--reference", "--origin", "--template",
        "--separate-git-dir", "--type", "--default", "--blob", "--sort"
    ]

    private static let alwaysAuditable: Set<String> = [
        "fetch", "pull", "push", "commit", "merge", "rebase", "reset", "revert", "cherry-pick",
        "add", "rm", "mv", "restore", "clean", "am", "clone", "init", "update-ref", "subtree",
        "switch", "checkout", "gc", "update-index"
    ]

    static func isAuditable(arguments: [String]) -> Bool {
        guard let (subcommand, rest) = commandParts(arguments) else { return false }
        if alwaysAuditable.contains(subcommand) { return true }
        let positionals = positionalArguments(rest)
        switch subcommand {
        case "apply":
            return !rest.contains("--check") && !rest.contains("--stat") && !rest.contains("--numstat")
                || rest.contains("--apply")
        case "stash":
            return !["list", "show"].contains(positionals.first ?? "push")
        case "branch":
            return isRefWrite(rest, positionals: positionals,
                              writeFlags: ["-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy",
                                           "-f", "--force", "-u", "--set-upstream-to", "--unset-upstream",
                                           "--edit-description", "--track", "--no-track"],
                              listFlags: ["--list", "-l", "--contains", "--no-contains", "--merged",
                                          "--no-merged", "--points-at", "--format", "--show-current", "-a",
                                          "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "--column"])
        case "tag":
            return isRefWrite(rest, positionals: positionals,
                              writeFlags: ["-d", "--delete", "-a", "--annotate", "-s", "--sign", "-f",
                                           "--force", "-m", "-F", "--message", "--file", "-u"],
                              listFlags: ["-l", "--list", "--contains", "--no-contains", "--merged",
                                          "--no-merged", "--points-at", "--format", "-n", "--column",
                                          "-v", "--verify"])
        case "remote":
            return ["add", "remove", "rm", "rename", "set-url", "set-head", "set-branches", "prune", "update"]
                .contains(positionals.first ?? "")
        case "worktree":
            return ["add", "remove", "move", "prune", "lock", "unlock", "repair"].contains(positionals.first ?? "")
        case "submodule":
            return !["status", "summary"].contains(positionals.first ?? "status")
        case "notes":
            return !["list", "show", "get-ref"].contains(positionals.first ?? "list")
        case "lfs":
            return ["push", "pull", "fetch", "install", "uninstall", "track", "untrack", "migrate", "prune", "checkout"]
                .contains(positionals.first ?? "")
        case "symbolic-ref":
            return rest.contains("-d") || rest.contains("--delete") || positionals.count >= 2
        case "config":
            return isConfigWrite(rest)
        default:
            return false
        }
    }

    static func title(arguments: [String]) -> String {
        guard let (subcommand, rest) = commandParts(arguments) else { return "Git" }
        let name = displayName(subcommand)
        let positionals = positionalArguments(rest)
        let paths = pathArguments(rest)
        let title: String
        switch subcommand {
        case "stash", "remote", "worktree", "submodule", "lfs", "notes":
            var words = [name]
            if let verb = positionals.first ?? (subcommand == "stash" ? "push" : nil) { words.append(verb) }
            if subcommand == "remote" || subcommand == "worktree", positionals.count > 1 {
                words.append(URL(fileURLWithPath: positionals[1]).lastPathComponent)
            }
            title = words.joined(separator: " ")
        case "commit", "add", "rm", "mv", "restore", "apply", "clean", "gc", "init", "update-index":
            switch paths.count {
            case 0: title = name
            case 1: title = "\(name) \(URL(fileURLWithPath: paths[0]).lastPathComponent)"
            default: title = "\(name) \(paths.count) files"
            }
        case "config":
            title = positionals.first.map { "\(name) \($0)" } ?? name
        default:
            title = positionals.first.map { "\(name) \($0)" } ?? name
        }
        return truncated(title, limit: 80)
    }

    /// The command as shown in the audit, without the leading `git`.
    static func displayCommand(arguments: [String]) -> String {
        GitCommandLogStore.sanitized(arguments: arguments)
            .map(GitCommandLogStore.shellQuoted)
            .joined(separator: " ")
    }

    static func redactedOutput(_ output: String) -> String {
        output.replacing(#/([A-Za-z][A-Za-z0-9+.\-]*://)[^/@\s]+@/#) { match in
            "\(match.output.1)<redacted>@"
        }
    }

    /// First output line, or a result description when Git printed nothing.
    static func summary(output: String, status: RepositoryActionAuditStatus, command: String) -> String {
        let line = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let line { return truncated(line, limit: summaryCharacterLimit) }
        switch status {
        case .succeeded:
            // A fetch that updates no refs prints nothing.
            let subcommand = commandParts(command.split(separator: " ").map(String.init))?.0
            return subcommand == "fetch" ? "Already up to date" : "Completed with no output"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    /// Skips global options such as `-c key=value` to find the subcommand.
    static func commandParts(_ arguments: [String]) -> (String, [String])? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if ["-c", "-C", "--git-dir", "--work-tree", "--namespace"].contains(argument) {
                index += 2
            } else if argument.hasPrefix("-") {
                index += 1
            } else {
                return (argument, Array(arguments[(index + 1)...]))
            }
        }
        return nil
    }

    private static func positionalArguments(_ rest: [String]) -> [String] {
        var result: [String] = []
        var skipNext = false
        for argument in rest {
            if skipNext { skipNext = false; continue }
            if argument == "--" { break }
            if optionsWithValue.contains(argument) { skipNext = true; continue }
            if argument.hasPrefix("-") { continue }
            result.append(argument)
        }
        return result
    }

    private static func pathArguments(_ rest: [String]) -> [String] {
        guard let separator = rest.firstIndex(of: "--") else { return [] }
        return Array(rest[(separator + 1)...])
    }

    private static func hasFlag(_ rest: [String], in flags: Set<String>) -> Bool {
        rest.contains { argument in
            flags.contains(argument) || flags.contains(String(argument.prefix { $0 != "=" }))
        }
    }

    private static func isRefWrite(
        _ rest: [String],
        positionals: [String],
        writeFlags: Set<String>,
        listFlags: Set<String>
    ) -> Bool {
        if hasFlag(rest, in: writeFlags) { return true }
        if hasFlag(rest, in: listFlags) { return false }
        return !positionals.isEmpty
    }

    private static func isConfigWrite(_ rest: [String]) -> Bool {
        let readFlags: Set<String> = ["--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l",
                                      "--get-color", "--get-colorbool"]
        let writeFlags: Set<String> = ["--unset", "--unset-all", "--add", "--replace-all", "--remove-section",
                                       "--rename-section", "--edit", "-e"]
        if hasFlag(rest, in: readFlags) { return false }
        if hasFlag(rest, in: writeFlags) { return true }
        var positionals: [String] = []
        var skipNext = false
        for argument in rest {
            if skipNext { skipNext = false; continue }
            if ["-f", "--file", "--blob", "--type", "--default"].contains(argument) { skipNext = true; continue }
            if argument.hasPrefix("-") { continue }
            positionals.append(argument)
        }
        switch positionals.first {
        case "get", "list": return false
        case "set", "unset", "rename-section", "remove-section", "edit": return true
        default: return positionals.count >= 2
        }
    }

    private static func displayName(_ subcommand: String) -> String {
        let spaced = subcommand == "cherry-pick" ? subcommand : subcommand.replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}

/// Session-only audit of mutating Git commands. Rows live on disk so long sessions do not
/// grow memory; the file is reset on first open and removed when the app terminates.
actor RepositoryActionAuditStore {
    static let shared = RepositoryActionAuditStore(url: sessionDatabaseURL)

    nonisolated static let sessionDatabaseURL: URL = {
        // XCTest hosts must never touch the app's session file.
        if FirebaseBootstrap.isRunningUnitTests {
            return FileManager.default.temporaryDirectory
                .appending(path: "CommitPlusTests-\(UUID().uuidString)/action-audit.sqlite")
        }
        return URL.applicationSupportDirectory.appending(path: "Commit+/LocalData/action-audit.sqlite")
    }()

    static let maximumRecordsPerRepository = 1_000

    private let url: URL
    private let postsNotifications: Bool
    private var connection: OpaquePointer?

    init(url: URL, postsNotifications: Bool = true) {
        self.url = url
        self.postsNotifications = postsNotifications
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    /// Synchronous so `applicationWillTerminate` can call it before the process exits.
    nonisolated static func removeSessionFile(at url: URL = sessionDatabaseURL) {
        for path in [url.path, url.path + "-journal", url.path + "-wal", url.path + "-shm"] {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func record(_ record: RepositoryActionAuditRecord) {
        let bounded = Self.bounded(record.output)
        let summary = RepositoryActionAudit.summary(output: bounded.text, status: record.status, command: record.command)
        do {
            let db = try database()
            try execute(db, """
                INSERT INTO audit_entries (repository_path, title, origin, command, summary, output,
                    output_truncated, status, finished_at, duration)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [
                    .text(record.repositoryPath), .text(record.title), .text(record.origin.rawValue),
                    .text(record.command), .text(summary), .text(bounded.text),
                    .integer(bounded.isTruncated ? 1 : 0), .text(record.status.rawValue),
                    .real(record.finishedAt.timeIntervalSince1970), .real(record.duration)
                ])
            try execute(db, """
                DELETE FROM audit_entries WHERE repository_path = ? AND id <= (
                    SELECT id FROM audit_entries WHERE repository_path = ? ORDER BY id DESC LIMIT 1 OFFSET ?)
                """, [.text(record.repositoryPath), .text(record.repositoryPath),
                      .integer(Int64(Self.maximumRecordsPerRepository))])
        } catch {
            // Auditing must never interfere with Git operations.
            return
        }
        guard postsNotifications else { return }
        NotificationCenter.default.post(
            name: .repositoryActionAuditDidRecord,
            object: nil,
            userInfo: ["repositoryPath": record.repositoryPath]
        )
    }

    func summaries(repositoryPath: String, limit: Int = maximumRecordsPerRepository) -> [RepositoryActionAuditSummary] {
        var result: [RepositoryActionAuditSummary] = []
        do {
            try execute(try database(), """
                SELECT id, title, origin, summary, status, finished_at FROM audit_entries
                WHERE repository_path = ? ORDER BY id DESC LIMIT ?
                """, [.text(repositoryPath), .integer(Int64(limit))]) { row in
                result.append(RepositoryActionAuditSummary(
                    id: sqlite3_column_int64(row, 0),
                    title: Self.text(row, 1),
                    origin: RepositoryActionAuditOrigin(rawValue: Self.text(row, 2)) ?? .user,
                    summary: Self.text(row, 3),
                    status: RepositoryActionAuditStatus(rawValue: Self.text(row, 4)) ?? .failed,
                    finishedAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 5))
                ))
            }
        } catch {
            return []
        }
        return result
    }

    func entry(id: Int64) -> RepositoryActionAuditEntry? {
        var result: RepositoryActionAuditEntry?
        try? execute(try database(), """
            SELECT id, title, origin, command, output, output_truncated, status, finished_at, duration, summary
            FROM audit_entries WHERE id = ?
            """, [.integer(id)]) { row in
            result = RepositoryActionAuditEntry(
                id: sqlite3_column_int64(row, 0),
                title: Self.text(row, 1),
                origin: RepositoryActionAuditOrigin(rawValue: Self.text(row, 2)) ?? .user,
                command: Self.text(row, 3),
                summary: Self.text(row, 9),
                output: Self.text(row, 4),
                isOutputTruncated: sqlite3_column_int(row, 5) != 0,
                status: RepositoryActionAuditStatus(rawValue: Self.text(row, 6)) ?? .failed,
                finishedAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 7)),
                duration: sqlite3_column_double(row, 8)
            )
        }
        return result
    }

    // MARK: - SQLite

    private enum Value {
        case text(String)
        case integer(Int64)
        case real(Double)
    }

    nonisolated private static func bounded(_ output: String) -> (text: String, isTruncated: Bool) {
        let bytes = Data(output.utf8)
        guard bytes.count > RepositoryActionAudit.outputByteLimit else { return (output, false) }
        // Decoding repairs a multi-byte character cut at the limit.
        return (String(decoding: bytes.prefix(RepositoryActionAudit.outputByteLimit), as: UTF8.self), true)
    }

    private func database() throws -> OpaquePointer {
        if let connection { return connection }
        // A file left by a previous run (for example after a crash) belongs to another session.
        Self.removeSessionFile(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var opened: OpaquePointer?
        let status = sqlite3_open(url.path, &opened)
        guard let db = opened else { throw failure("Could not open the action audit.") }
        guard status == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw failure(message)
        }
        sqlite3_busy_timeout(db, 3_000)
        do {
            try execute(db, """
                CREATE TABLE audit_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, repository_path TEXT NOT NULL,
                    title TEXT NOT NULL, origin TEXT NOT NULL, command TEXT NOT NULL, summary TEXT NOT NULL,
                    output TEXT NOT NULL, output_truncated INTEGER NOT NULL, status TEXT NOT NULL,
                    finished_at REAL NOT NULL, duration REAL NOT NULL)
                """)
            try execute(db, "CREATE INDEX audit_entries_repository ON audit_entries (repository_path, id)")
        } catch {
            sqlite3_close(db)
            throw error
        }
        connection = db
        return db
    }

    private func execute(
        _ db: OpaquePointer,
        _ sql: String,
        _ values: [Value] = [],
        row: (OpaquePointer) throws -> Void = { _ in }
    ) throws {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else {
            throw failure(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch value {
            case .text(let text):
                status = sqlite3_bind_text(statement, position, text, -1, transient)
            case .integer(let integer):
                status = sqlite3_bind_int64(statement, position, integer)
            case .real(let real):
                status = sqlite3_bind_double(statement, position, real)
            }
            guard status == SQLITE_OK else { throw failure(String(cString: sqlite3_errmsg(db))) }
        }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            try row(statement)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure(String(cString: sqlite3_errmsg(db))) }
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: value, count: Int(sqlite3_column_bytes(statement, index))), as: UTF8.self)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "RepositoryActionAuditStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
