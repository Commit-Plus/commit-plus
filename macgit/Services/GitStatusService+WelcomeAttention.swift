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
    func welcomeAttention(for repository: RecentRepository) async throws -> WelcomeRepositoryAttention {
        var result = WelcomeRepositoryAttention(url: repository.url, name: repository.name)
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_NO_LAZY_FETCH"] = "1"
        guard FileManager.default.fileExists(atPath: repository.url.appendingPathComponent(".git").path) else {
            result.unavailable = true
            return result
        }
        do {
            let output = try await runGit(
                arguments: ["status", "--porcelain=v2", "--branch", "--ahead-behind", "--untracked-files=normal", "--ignore-submodules=all"],
                in: repository.url, environment: environment
            )
            result = Self.parseWelcomeAttention(output, repository: repository)
            try Task.checkCancellation()
            let gitDir = try await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-dir"],
                                          in: repository.url, environment: environment)
            let directory = URL(fileURLWithPath: gitDir.trimmingCharacters(in: .whitespacesAndNewlines))
            for (path, operation) in [("rebase-merge", "Rebase"), ("rebase-apply", "Rebase / apply"),
                                      ("MERGE_HEAD", "Merge"), ("CHERRY_PICK_HEAD", "Cherry-pick"),
                                      ("REVERT_HEAD", "Revert"), ("sequencer", "Sequenced operation")] {
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path) {
                    result.operation = operation
                    break
                }
            }
        } catch {
            try Task.checkCancellation()
            result.error = "Local status could not be fully checked"
        }
        return result
    }

    static func parseWelcomeAttention(_ output: String, repository: RecentRepository) -> WelcomeRepositoryAttention {
        var result = WelcomeRepositoryAttention(url: repository.url, name: repository.name)
        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let branch = String(line.dropFirst("# branch.head ".count))
                result.branch = branch == "(detached)" ? "Detached HEAD" : branch
            } else if line.hasPrefix("# branch.ab ") {
                let values = line.dropFirst("# branch.ab ".count).split(separator: " ")
                if values.count == 2, let ahead = Int(values[0]), let behind = Int(values[1]) {
                    result.ahead = max(0, ahead)
                    result.behind = abs(behind)
                } else {
                    result.error = "Upstream status could not be read"
                }
            } else if line.hasPrefix("u ") {
                result.conflicts += 1
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("? ") {
                result.hasUncommittedChanges = true
            }
        }
        return result
    }
}
