//
//  GitStatusService+Branch.swift
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

struct BranchSyncStatus: Equatable {
    let ahead: Int   // local commits not on remote
    let behind: Int  // remote commits not on local
}

extension GitStatusService {
    func currentBranch(in repositoryURL: URL) async -> String? {
        let showCurrentOutput = try? await runGit(arguments: ["branch", "--show-current"], in: repositoryURL)
        if let branch = GitCurrentBranchResolver.resolve(
            showCurrentOutput: showCurrentOutput,
            abbreviatedHeadOutput: nil
        ) {
            return branch
        }

        let abbreviatedHeadOutput = try? await runGit(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], in: repositoryURL)
        return GitCurrentBranchResolver.resolve(
            showCurrentOutput: nil,
            abbreviatedHeadOutput: abbreviatedHeadOutput
        )
    }

    func localBranches(in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["branch", "--format=%(refname:short)"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    func cachedLocalBranches(in repositoryURL: URL) async -> [String] {
        await branchListCache.values(for: .local(repositoryURL)) { [repositoryURL] in
            await self.localBranches(in: repositoryURL)
        }
    }

    func invalidateBranchListCache(in repositoryURL: URL) async {
        await branchListCache.invalidate(repositoryURL: repositoryURL)
    }

    func upstreamBranch(for branch: String, in repositoryURL: URL) async -> String? {
        let upstream = (try? await runGit(arguments: ["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = upstream, !u.isEmpty, !u.contains("fatal:") else { return nil }
        return u
    }

    func localBranchUpstreams(in repositoryURL: URL) async -> [String: String] {
        let format = "%(refname:short) %(upstream:short)"
        let output = (try? await runGit(arguments: ["for-each-ref", "refs/heads/", "--format=\(format)"], in: repositoryURL)) ?? ""
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                .map { String($0) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            result[parts[0]] = parts[1]
        }
        return result
    }

    func setUpstream(upstream: String, branch: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["branch", "--set-upstream-to", upstream, branch], in: repositoryURL)
    }

    func unsetUpstream(branch: String, in repositoryURL: URL) async throws {
        _ = try await runGit(arguments: ["branch", "--unset-upstream", branch], in: repositoryURL)
    }

    func createBranch(name: String, checkout: Bool, commit: String?, in repositoryURL: URL) async throws -> String {
        let output: String
        if checkout {
            var arguments = ["checkout", "-b", name]
            if let commit = commit, !commit.isEmpty {
                arguments.append(commit)
            }
            output = try await runGit(arguments: arguments, in: repositoryURL)
        } else {
            var arguments = ["branch", name]
            if let commit = commit, !commit.isEmpty {
                arguments.append(commit)
            }
            output = try await runGit(arguments: arguments, in: repositoryURL)
        }
        await invalidateBranchListCache(in: repositoryURL)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .repositoryBranchDidCreate,
                object: nil,
                userInfo: [
                    "repositoryURL": repositoryURL,
                    "branchName": name
                ]
            )
        }
        return output
    }

    func deleteBranch(name: String, force: Bool, in repositoryURL: URL) async throws -> String {
        let flag = force ? "-D" : "-d"
        let output = try await runGit(arguments: ["branch", flag, name], in: repositoryURL)
        await invalidateBranchListCache(in: repositoryURL)
        return output
    }

    func renameBranch(from oldName: String, to newName: String, in repositoryURL: URL) async throws -> String {
        let output = try await runGit(arguments: ["branch", "-m", oldName, newName], in: repositoryURL)
        await invalidateBranchListCache(in: repositoryURL)
        return output
    }

    func deleteRemoteBranch(remote: String, name: String, in repositoryURL: URL) async throws -> String {
        let output = try await runGit(arguments: ["push", remote, "--delete", name], in: repositoryURL)
        await branchListCache.invalidateRemote(repositoryURL: repositoryURL, remote: remote)
        return output
    }

    func tags(in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["tag", "--list"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    func branchSyncStatus(for branch: String, in repositoryURL: URL) async -> BranchSyncStatus? {
        guard let comparisonRef = await comparisonRef(for: branch, in: repositoryURL) else {
            print("[branchSyncStatus] No upstream or matching remote-tracking branch for branch: \(branch)")
            return nil
        }

        return await branchSyncStatus(
            for: branch,
            comparedTo: comparisonRef,
            in: repositoryURL
        )
    }

    func branchSyncStatuses(
        for branches: [String],
        in repositoryURL: URL
    ) async -> [String: BranchSyncStatus] {
        let requestedBranches = Set(branches.filter { !$0.isEmpty })
        guard !requestedBranches.isEmpty else { return [:] }

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        let format = "%00%(refname:short)%00%(upstream:short)%00%(upstream:track,nobracket)%00"

        guard let output = try? await runGit(
            arguments: ["for-each-ref", "refs/heads/", "--format=\(format)"],
            in: repositoryURL,
            environment: environment
        ) else {
            return await branchSyncStatusesIndividually(
                for: Array(requestedBranches),
                in: repositoryURL
            )
        }

        let trackingRecords = parseBranchTrackingRecords(output)
        var statuses: [String: BranchSyncStatus] = [:]
        var branchesWithoutUpstream: [String] = []
        var unresolvedBranches: [String] = []

        for branch in requestedBranches {
            guard let record = trackingRecords[branch] else {
                unresolvedBranches.append(branch)
                continue
            }

            if record.upstream.isEmpty {
                branchesWithoutUpstream.append(branch)
            } else if let status = Self.parseTrackingStatus(record.tracking) {
                statuses[branch] = status
            }
        }

        let fallbackComparisonRefs = await matchingRemoteTrackingBranches(
            for: branchesWithoutUpstream,
            in: repositoryURL
        )
        let fallbackStatuses = await branchSyncStatuses(
            for: fallbackComparisonRefs.map { (branch: $0.key, comparisonRef: $0.value) },
            in: repositoryURL
        )
        statuses.merge(fallbackStatuses) { _, new in new }

        if !unresolvedBranches.isEmpty {
            let unresolvedStatuses = await branchSyncStatusesIndividually(
                for: unresolvedBranches,
                in: repositoryURL
            )
            statuses.merge(unresolvedStatuses) { _, new in new }
        }

        return statuses
    }

    func branchSyncStatus(
        for branch: String,
        comparedTo comparisonRef: String,
        in repositoryURL: URL
    ) async -> BranchSyncStatus? {

        // Use a single symmetric-difference command to get both counts atomically
        // Output format: "behind\tahead"
        let output = (try? await runGit(
            arguments: ["rev-list", "--count", "--left-right", "\(comparisonRef)...\(branch)"],
            in: repositoryURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let line = output, !line.isEmpty else {
            print("[branchSyncStatus] Empty output for branch: \(branch), comparison ref: \(comparisonRef)")
            return nil
        }

        let parts = line.split(separator: "\t").map { String($0) }
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            print("[branchSyncStatus] Invalid output for branch: \(branch), output: \(line)")
            return nil
        }

        // If both are zero, return nil to hide the badge
        if ahead == 0 && behind == 0 {
            return nil
        }

        print("[branchSyncStatus] Branch: \(branch), comparison ref: \(comparisonRef), ahead: \(ahead), behind: \(behind)")
        return BranchSyncStatus(ahead: ahead, behind: behind)
    }

    func comparisonRef(for branch: String, in repositoryURL: URL) async -> String? {
        if let upstream = await upstreamBranch(for: branch, in: repositoryURL), !upstream.isEmpty {
            return upstream
        }

        return await matchingRemoteTrackingBranch(for: branch, in: repositoryURL)
    }

    private func matchingRemoteTrackingBranch(for branch: String, in repositoryURL: URL) async -> String? {
        let remotes = await remotes(in: repositoryURL)
        let matches = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            for remote in remotes {
                group.addTask {
                    let ref = "\(remote)/\(branch)"
                    let output = try? await self.runGit(
                        arguments: ["rev-parse", "--verify", "--quiet", "refs/remotes/\(ref)"],
                        in: repositoryURL
                    )
                    guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    return ref
                }
            }

            var matches: [String] = []
            for await match in group {
                if let match {
                    matches.append(match)
                }
            }
            return matches
        }

        if matches.contains("origin/\(branch)") {
            return "origin/\(branch)"
        }

        return matches.count == 1 ? matches[0] : nil
    }

    private func parseBranchTrackingRecords(_ output: String) -> [String: (upstream: String, tracking: String)] {
        var records: [String: (upstream: String, tracking: String)] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { continue }

            let branch = fields[1]
            guard !branch.isEmpty else { continue }
            records[branch] = (upstream: fields[2], tracking: fields[3])
        }

        return records
    }

    private static func parseTrackingStatus(_ tracking: String) -> BranchSyncStatus? {
        var ahead = 0
        var behind = 0

        for component in tracking.split(separator: ",") {
            let fields = component
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 1)
            guard fields.count == 2, let count = Int(fields[1]) else { continue }

            switch fields[0] {
            case "ahead":
                ahead = count
            case "behind":
                behind = count
            default:
                continue
            }
        }

        guard ahead > 0 || behind > 0 else { return nil }
        return BranchSyncStatus(ahead: ahead, behind: behind)
    }

    private func matchingRemoteTrackingBranches(
        for branches: [String],
        in repositoryURL: URL
    ) async -> [String: String] {
        guard !branches.isEmpty else { return [:] }

        async let remoteNames = remotes(in: repositoryURL)
        async let remoteRefsOutput = try? runGit(
            arguments: ["for-each-ref", "refs/remotes/", "--format=%(refname:short)"],
            in: repositoryURL
        )
        let (remotes, output) = await (remoteNames, remoteRefsOutput)
        let remoteRefs = Set((output ?? "").split(separator: "\n").map(String.init))

        var result: [String: String] = [:]
        for branch in branches {
            let matches = remotes
                .map { "\($0)/\(branch)" }
                .filter(remoteRefs.contains)

            if matches.contains("origin/\(branch)") {
                result[branch] = "origin/\(branch)"
            } else if matches.count == 1 {
                result[branch] = matches[0]
            }
        }
        return result
    }

    private func branchSyncStatusesIndividually(
        for branches: [String],
        in repositoryURL: URL
    ) async -> [String: BranchSyncStatus] {
        await withTaskGroup(of: (String, BranchSyncStatus?).self, returning: [String: BranchSyncStatus].self) { group in
            var iterator = branches.makeIterator()
            let concurrencyLimit = min(4, branches.count)

            for _ in 0..<concurrencyLimit {
                guard let branch = iterator.next() else { break }
                group.addTask {
                    (branch, await self.branchSyncStatus(for: branch, in: repositoryURL))
                }
            }

            var statuses: [String: BranchSyncStatus] = [:]
            while let (branch, status) = await group.next() {
                if let status {
                    statuses[branch] = status
                }
                if let nextBranch = iterator.next() {
                    group.addTask {
                        (nextBranch, await self.branchSyncStatus(for: nextBranch, in: repositoryURL))
                    }
                }
            }
            return statuses
        }
    }

    private func branchSyncStatuses(
        for comparisons: [(branch: String, comparisonRef: String)],
        in repositoryURL: URL
    ) async -> [String: BranchSyncStatus] {
        await withTaskGroup(of: (String, BranchSyncStatus?).self, returning: [String: BranchSyncStatus].self) { group in
            var iterator = comparisons.makeIterator()
            let concurrencyLimit = min(4, comparisons.count)

            for _ in 0..<concurrencyLimit {
                guard let comparison = iterator.next() else { break }
                group.addTask {
                    let status = await self.branchSyncStatus(
                        for: comparison.branch,
                        comparedTo: comparison.comparisonRef,
                        in: repositoryURL
                    )
                    return (comparison.branch, status)
                }
            }

            var statuses: [String: BranchSyncStatus] = [:]
            while let (branch, status) = await group.next() {
                if let status {
                    statuses[branch] = status
                }
                if let comparison = iterator.next() {
                    group.addTask {
                        let status = await self.branchSyncStatus(
                            for: comparison.branch,
                            comparedTo: comparison.comparisonRef,
                            in: repositoryURL
                        )
                        return (comparison.branch, status)
                    }
                }
            }
            return statuses
        }
    }

}
