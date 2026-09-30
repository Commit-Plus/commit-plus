// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func repoPickerStatus(in repositoryURL: URL) async -> RepoPickerStatusSnapshot {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_NO_LAZY_FETCH"] = "1"

        let output = try? await runGit(
            arguments: [
                "status", "--porcelain=v2", "--branch", "--ahead-behind",
                "--untracked-files=all"
            ],
            in: repositoryURL,
            environment: environment
        )

        guard let output else {
            async let branch = currentBranch(in: repositoryURL)
            async let changedFileCount = uncommittedChangeCount(in: repositoryURL)
            async let counts = aheadBehindCount(in: repositoryURL)
            return await RepoPickerStatusSnapshot(
                currentBranch: branch,
                changedFileCount: changedFileCount,
                behindCount: counts.behind,
                aheadCount: counts.ahead,
                includesAheadBehind: true
            )
        }

        var snapshot = Self.parseRepoPickerStatus(output)
        if !snapshot.includesAheadBehind, snapshot.currentBranch != nil {
            let counts = await aheadBehindCount(in: repositoryURL)
            snapshot.behindCount = counts.behind
            snapshot.aheadCount = counts.ahead
            snapshot.includesAheadBehind = true
        }
        return snapshot
    }

    nonisolated static func parseRepoPickerStatus(_ output: String) -> RepoPickerStatusSnapshot {
        var snapshot = RepoPickerStatusSnapshot(
            currentBranch: nil,
            changedFileCount: 0,
            behindCount: 0,
            aheadCount: 0,
            includesAheadBehind: false
        )

        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let branch = line.dropFirst("# branch.head ".count)
                snapshot.currentBranch = branch == "(detached)" ? nil : String(branch)
            } else if line.hasPrefix("# branch.ab ") {
                let values = line.dropFirst("# branch.ab ".count).split(separator: " ")
                if values.count == 2,
                   let ahead = Int(values[0]),
                   let behind = Int(values[1]) {
                    snapshot.aheadCount = max(0, ahead)
                    snapshot.behindCount = abs(behind)
                    snapshot.includesAheadBehind = true
                }
            } else if line.hasPrefix("1 ")
                        || line.hasPrefix("2 ")
                        || line.hasPrefix("u ")
                        || line.hasPrefix("? ") {
                snapshot.changedFileCount += 1
            }
        }

        return snapshot
    }
}
