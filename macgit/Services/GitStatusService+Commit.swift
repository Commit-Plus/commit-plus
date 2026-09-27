//
//  GitStatusService+Commit.swift
//  macgit
//

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

extension GitStatusService {
    enum GitUserScope: Equatable {
        case local
        case global
    }

    struct GitUserConfiguration: Equatable, Sendable {
        let name: String
        let email: String
    }

    func gitUserConfiguration(in repositoryURL: URL, scope: GitUserScope) async -> GitUserConfiguration? {
        let scopeArgument = scope == .local ? "--local" : "--global"
        let name = (try? await runGit(arguments: ["config", scopeArgument, "--get", "user.name"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (try? await runGit(arguments: ["config", scopeArgument, "--get", "user.email"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty, let email, !email.isEmpty else { return nil }
        return GitUserConfiguration(name: name, email: email)
    }

    func updateGitUserConfiguration(
        useGlobalSettings: Bool,
        name: String,
        email: String,
        in repositoryURL: URL
    ) async throws {
        if useGlobalSettings {
            _ = try? await runGit(arguments: ["config", "--local", "--unset-all", "user.name"], in: repositoryURL)
            _ = try? await runGit(arguments: ["config", "--local", "--unset-all", "user.email"], in: repositoryURL)
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            throw GitError.commandFailed("User name and email are required when global user settings are disabled.")
        }
        _ = try await runGit(arguments: ["config", "--local", "user.name", trimmedName], in: repositoryURL)
        _ = try await runGit(arguments: ["config", "--local", "user.email", trimmedEmail], in: repositoryURL)
    }

    func squashCommits(_ commits: [String], message: String, in repositoryURL: URL) async throws {
        guard commits.count >= 2, let oldestCommit = commits.last else {
            throw GitError.commandFailed("Select at least two commits to squash.")
        }

        let parent = try await runGit(
            arguments: ["rev-parse", "\(oldestCommit)^"],
            in: repositoryURL
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !parent.isEmpty else {
            throw GitError.commandFailed("The selected commits do not have a parent commit.")
        }

        _ = try await runGit(arguments: ["reset", "--soft", parent], in: repositoryURL)
        try await commit(message: message, in: repositoryURL)
    }

    func commit(
        message: String,
        in repositoryURL: URL,
        amend: Bool = false,
        noVerify: Bool = false,
        signOff: Bool = false,
        allowEmpty: Bool = false
    ) async throws {
        try await validateLFSCommitAttributes(in: repositoryURL)
        var arguments = ["commit"]
        if allowEmpty { arguments.append("--allow-empty") }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append("--allow-empty-message")
        }
        arguments.append(contentsOf: ["-m", message])
        if amend { arguments.append("--amend") }
        if noVerify { arguments.append("--no-verify") }
        if signOff { arguments.append("--signoff") }
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    func gitUser(in repositoryURL: URL) async -> String? {
        let name = (try? await runGit(arguments: ["config", "user.name"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (try? await runGit(arguments: ["config", "user.email"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = name, !n.isEmpty, let e = email, !e.isEmpty else { return nil }
        return "\(n) <\(e)>"
    }

    func recentCommits(limit: Int, in repositoryURL: URL) async -> [(hash: String, message: String)] {
        let output = (try? await runGit(arguments: ["log", "--oneline", "-\(limit)"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            // Format: "<short-hash> <message>"
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            guard let hash = parts.first else { return nil }
            let message = parts.count > 1 ? String(parts[1]) : ""
            return (hash: String(hash), message: message)
        }
    }

    func recentCommits(in repositoryURL: URL, count: Int = 10) async -> [(hash: String, message: String)] {
        let output = (try? await runGit(arguments: ["log", "--oneline", "-\(count)"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let hash = parts.first else { return nil }
            let message = parts.count > 1 ? String(parts[1]) : ""
            return (hash: String(hash), message: message)
        }
    }

    func commitInfo(for identifier: String, in repositoryURL: URL) async -> (hash: String, message: String)? {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty,
              trimmedIdentifier.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }),
              trimmedIdentifier.count <= 40 else {
            return nil
        }

        let resolvedHash = (try? await runGit(
            arguments: ["rev-parse", "--verify", "\(trimmedIdentifier)^{commit}"],
            in: repositoryURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedHash, !resolvedHash.isEmpty else {
            return nil
        }

        guard let output = try? await runGit(
            arguments: ["show", "-s", "--format=%H%x1f%s", resolvedHash],
            in: repositoryURL
        ),
        let separator = output.firstIndex(of: "\u{1F}") else {
            return nil
        }

        let hash = output[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return nil }

        let messageStart = output.index(after: separator)
        let message = output[messageStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (hash: String(hash), message: String(message))
    }

    func commitInfoIncludingRemotes(for identifier: String, in repositoryURL: URL) async -> (hash: String, message: String)? {
        if let localCommit = await commitInfo(for: identifier, in: repositoryURL) {
            return localCommit
        }

        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedIdentifier.count >= 7 else { return nil }

        _ = try? await runGit(arguments: ["fetch", "--all", "--quiet"], in: repositoryURL)
        return await commitInfo(for: trimmedIdentifier, in: repositoryURL)
    }

    // MARK: - Commit History

    func commitHistory(allBranches: Bool, in repositoryURL: URL) async -> [Commit] {
        await commitHistory(allBranches: allBranches, limit: 500, skip: 0, in: repositoryURL)
    }

    func commitHistory(allBranches: Bool, limit: Int, skip: Int = 0, in repositoryURL: URL) async -> [Commit] {
        var arguments = ["log", "--topo-order"]
        if allBranches {
            arguments.append("--all")
        }
        arguments.append(contentsOf: [
            "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D",
            "--date=iso-strict",
            "--max-count", "\(limit)"
        ])
        if skip > 0 {
            arguments.append(contentsOf: ["--skip", "\(skip)"])
        }
        let output = (try? await runGit(arguments: arguments, in: repositoryURL)) ?? ""
        return parseCommitLog(output)
    }

    func commitHistory(branch: String, in repositoryURL: URL) async -> [Commit] {
        await commitHistory(branch: branch, limit: 500, skip: 0, in: repositoryURL)
    }

    func commitHistory(branch: String, limit: Int, skip: Int = 0, in repositoryURL: URL) async -> [Commit] {
        let arguments = commitLogArguments(
            allBranches: false,
            branch: branch,
            limit: limit,
            skip: skip
        )

        let output = (try? await runGit(arguments: arguments, in: repositoryURL)) ?? ""
        return parseCommitLog(output)
    }

    func fullCommitMessage(for hash: String, in repositoryURL: URL) async -> String? {
        let trimmedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHash.isEmpty else { return nil }

        let output = try? await runGit(
            arguments: ["show", "-s", "--no-notes", "--format=%B", trimmedHash],
            in: repositoryURL
        )
        guard let output else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func searchCommitHistory(
        allBranches: Bool,
        query: String,
        limit: Int,
        skip: Int = 0,
        in repositoryURL: URL
    ) async -> [Commit] {
        await searchCommitHistory(
            allBranches: allBranches,
            branch: nil,
            query: query,
            limit: limit,
            skip: skip,
            in: repositoryURL
        )
    }

    func searchCommitHistory(
        branch: String,
        query: String,
        limit: Int,
        skip: Int = 0,
        in repositoryURL: URL
    ) async -> [Commit] {
        await searchCommitHistory(
            allBranches: false,
            branch: branch,
            query: query,
            limit: limit,
            skip: skip,
            in: repositoryURL
        )
    }

    func tipHash(for ref: String, in repositoryURL: URL) async -> String? {
        let output = (try? await runGit(arguments: ["rev-parse", "\(ref)^{commit}"], in: repositoryURL))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output = output, !output.isEmpty else { return nil }
        return output
    }

    func aheadBehindCount(in repositoryURL: URL) async -> (ahead: Int, behind: Int) {
        // Pull and Push badges describe only the checked-out branch. Prefer
        // the configured upstream, falling back to an unambiguous matching
        // remote-tracking branch for newly published branches.
        guard let branch = await currentBranch(in: repositoryURL),
              let comparisonRef = await comparisonRef(for: branch, in: repositoryURL) else {
            return (ahead: 0, behind: 0)
        }

        let output = (try? await runGit(
            arguments: ["rev-list", "--count", "--left-right", "\(comparisonRef)...HEAD"],
            in: repositoryURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = output.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            return (ahead: 0, behind: 0)
        }
        return (ahead: ahead, behind: behind)
    }

    func parseCommitLog(_ raw: String) -> [Commit] {
        let dateFormatter = ISO8601DateFormatter()
        var commits: [Commit] = []
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "\u{0000}", omittingEmptySubsequences: false)
            guard parts.count >= 6 else { continue }
            let hash = String(parts[0])
            let parentStr = String(parts[1])
            let parents = parentStr.isEmpty ? [] : parentStr.split(separator: " ").map { String($0) }
            let message = String(parts[2])
            let author = String(parts[3])
            let email = String(parts[4])
            let dateStr = String(parts[5])
            let refsPart = parts.count > 6 ? String(parts[6]) : ""
            let refs = refsPart.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let date = dateFormatter.date(from: dateStr) ?? Date()
            commits.append(Commit(hash: hash, parents: parents, message: message, author: author, email: email, date: date, refs: refs))
        }
        return commits
    }

    private func searchCommitHistory(
        allBranches: Bool,
        branch: String?,
        query: String,
        limit: Int,
        skip: Int,
        in repositoryURL: URL
    ) async -> [Commit] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let authorQuery = NSRegularExpression.escapedPattern(for: normalizedQuery)
        let authorLimit = max(limit + skip + limit, limit)

        let authorOutput = (try? await runGit(
            arguments: commitLogArguments(
                allBranches: allBranches,
                branch: branch,
                authorQuery: authorQuery,
                limit: authorLimit,
                skip: 0
            ),
            in: repositoryURL
        )) ?? ""
        let authorMatches = parseCommitLog(authorOutput)

        let orderedHashesOutput = (try? await runGit(
            arguments: orderedCommitHashesArguments(
                allBranches: allBranches,
                branch: branch
            ),
            in: repositoryURL
        )) ?? ""
        let orderedHashes = orderedHashesOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let lowercaseQuery = normalizedQuery.lowercased()
        let matchingHashes = orderedHashes.filter { $0.lowercased().hasPrefix(lowercaseQuery) }
        let pageHashes = Array(matchingHashes.prefix(skip + limit + limit))

        let hashOutput: String
        if pageHashes.isEmpty {
            hashOutput = ""
        } else {
            hashOutput = (try? await runGit(
                arguments: [
                    "log", "--no-walk",
                    "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D",
                    "--date=iso-strict"
                ] + pageHashes,
                in: repositoryURL
            )) ?? ""
        }

        var commitsByHash: [String: Commit] = [:]
        for commit in authorMatches {
            commitsByHash[commit.hash] = commit
        }
        for commit in parseCommitLog(hashOutput) {
            commitsByHash[commit.hash] = commit
        }

        let orderedMatches = orderedHashes.compactMap { commitsByHash[$0] }
        return Array(orderedMatches.dropFirst(skip).prefix(limit))
    }

    private func commitLogArguments(
        allBranches: Bool,
        branch: String? = nil,
        authorQuery: String? = nil,
        limit: Int,
        skip: Int = 0
    ) -> [String] {
        var arguments = baseCommitLogArguments(allBranches: allBranches, branch: branch)
        if let authorQuery {
            arguments.append(contentsOf: ["--author", authorQuery, "-i"])
        }
        arguments.append(contentsOf: ["--max-count", "\(limit)"])
        if skip > 0 {
            arguments.append(contentsOf: ["--skip", "\(skip)"])
        }
        return arguments
    }

    private func orderedCommitHashesArguments(
        allBranches: Bool,
        branch: String? = nil
    ) -> [String] {
        var arguments = baseCommitLogArguments(
            allBranches: allBranches,
            branch: branch,
            format: "%H"
        )
        arguments.removeAll { $0 == "--date=iso-strict" }
        return arguments
    }

    private func baseCommitLogArguments(
        allBranches: Bool,
        branch: String? = nil,
        format: String = "%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D"
    ) -> [String] {
        var arguments = ["log", "--topo-order"]
        if allBranches {
            arguments.append("--all")
        } else if let branch {
            arguments.append(branch)
        }
        arguments.append(contentsOf: [
            "--format=\(format)",
            "--date=iso-strict"
        ])
        return arguments
    }
}
