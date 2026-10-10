//
//  GitStatusService+MergeStash.swift
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
    func isMergeInProgress(in repositoryURL: URL) async -> Bool {
        guard let mergeHead = try? await runGit(
            arguments: ["rev-parse", "--verify", "MERGE_HEAD"],
            in: repositoryURL
        ) else {
            return false
        }
        return !mergeHead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func mergeCommitMessage(in repositoryURL: URL) async -> String {
        guard let path = try? await runGit(
            arguments: ["rev-parse", "--git-path", "MERGE_MSG"],
            in: repositoryURL
        ) else {
            return ""
        }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "" }
        let messageURL = trimmedPath.hasPrefix("/")
            ? URL(fileURLWithPath: trimmedPath)
            : repositoryURL.appendingPathComponent(trimmedPath)
        return (try? String(contentsOf: messageURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func abortMerge(in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["merge", "--abort"], in: repositoryURL)
    }

    func merge(branch: String, options: MergeOptions, in repositoryURL: URL) async throws -> String {
        var arguments = ["merge"]
        if options.noFastForward { arguments.append("--no-ff") }
        if options.squash { arguments.append("--squash") }
        if !options.squash && !options.message.isEmpty {
            arguments.append("-m")
            arguments.append(options.message)
        }
        arguments.append(branch)
        return try await runGit(arguments: arguments, in: repositoryURL)
    }

    func stash(options: StashOptions, in repositoryURL: URL) async throws {
        var arguments = ["stash", "push"]
        if options.keepIndex { arguments.append("--keep-index") }
        if options.includeUntracked { arguments.append("--include-untracked") }
        if !options.message.isEmpty {
            arguments.append("-m")
            arguments.append(options.message)
        }
        let normalizedPaths = uniqueNonEmptyPaths(options.paths)
        if !normalizedPaths.isEmpty {
            arguments.append("--")
            arguments.append(contentsOf: normalizedPaths)
        }
        _ = try await runGit(arguments: arguments, in: repositoryURL)
    }

    private func uniqueNonEmptyPaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { path in
            !path.isEmpty && seen.insert(path).inserted
        }
    }

    func stashes(in repositoryURL: URL) async -> [StashEntry] {
        let output = (try? await runGit(arguments: ["stash", "list", "--format=%gd%x1f%H%x1f%gs"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{001f}", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }

            let ref = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let objectID = String(parts[1])
            let summary = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ref.isEmpty else { return nil }

            let parsed = parseStashSummary(summary)
            return StashEntry(ref: ref, branchName: parsed.branchName, description: parsed.description, objectID: objectID)
        }
    }

    func applyStash(ref: String, dropAfterApplying: Bool = false, in repositoryURL: URL) async throws {
        let command = dropAfterApplying ? "pop" : "apply"
        _ = try await runGit(arguments: ["stash", command, ref], in: repositoryURL)
    }

    func dropStash(ref: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["stash", "drop", ref], in: repositoryURL)
    }

    private func parseStashSummary(_ summary: String) -> (branchName: String, description: String) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix: String
        if trimmed.hasPrefix("WIP on ") {
            prefix = "WIP on "
        } else if trimmed.hasPrefix("On ") {
            prefix = "On "
        } else {
            return ("", trimmed)
        }

        let remainder = String(trimmed.dropFirst(prefix.count))
        guard let colonIndex = remainder.firstIndex(of: ":") else {
            return (remainder.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }

        let branchName = String(remainder[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionStart = remainder.index(after: colonIndex)
        let description = String(remainder[descriptionStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (branchName, description)
    }
}
