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

nonisolated struct CurrentBranchIntegrationStatus: Equatable, Sendable {
    let branch: String
    let remote: String
    let upstreamRef: String?
    let upstreamBehindCount: Int
    let baseBranch: String?
    let baseRef: String?
    let baseBehindCount: Int
    let predictedBaseConflictPaths: Set<String>
    let baseIncomingChangePaths: Set<String>

    var predictsBaseConflict: Bool {
        !predictedBaseConflictPaths.isEmpty
    }

    var potentialConflictPaths: Set<String> {
        predictedBaseConflictPaths.union(baseIncomingChangePaths)
    }

    var needsUpdate: Bool {
        upstreamBehindCount > 0 || baseBehindCount > 0
    }
}

extension GitStatusService {
    func potentialConflictFileAnalysis(
        for file: StatusFile,
        status: CurrentBranchIntegrationStatus,
        in repositoryURL: URL
    ) async -> PotentialConflictFileAnalysis {
        let exactAnalysis = await exactConflictPreview(
            for: file,
            currentRef: status.branch,
            incomingRef: status.baseRef,
            in: repositoryURL
        )

        return PotentialConflictFileAnalysis(
            conflictBlocks: exactAnalysis.blocks,
            exactAnalysisPerformed: exactAnalysis.wasPerformed
        )
    }

    func currentBranchIntegrationStatus(
        branch: String,
        preferredRemote: String?,
        gitFlowConfiguration: GitFlowConfiguration,
        in repositoryURL: URL
    ) async -> CurrentBranchIntegrationStatus? {
        guard !branch.isEmpty else { return nil }

        let upstreamRef = await upstreamBranch(for: branch, in: repositoryURL)
        let upstreamRemote = upstreamRef.flatMap(Self.remoteName(from:))
        let remote = await currentBranchIntegrationRemote(
            upstreamRemote: upstreamRemote,
            preferredRemote: preferredRemote,
            in: repositoryURL
        )
        guard let remote else { return nil }

        let upstreamStatus: BranchSyncStatus?
        if let upstreamRef {
            upstreamStatus = await branchSyncStatus(
                for: branch,
                comparedTo: upstreamRef,
                in: repositoryURL
            )
        } else {
            upstreamStatus = nil
        }
        let upstreamBehindCount = upstreamRef == nil ? 0 : (upstreamStatus?.behind ?? 0)
        let baseBranch = await currentBranchBaseBranch(
            branch: branch,
            remote: remote,
            gitFlowConfiguration: gitFlowConfiguration,
            in: repositoryURL
        )
        let baseRef = baseBranch.map { "\(remote)/\($0)" }

        var baseBehindCount = 0
        var predictedBaseConflictPaths: Set<String> = []
        var baseIncomingChangePaths: Set<String> = []
        if let baseRef,
           baseRef != upstreamRef,
           baseBranch != branch,
           await tipHash(for: baseRef, in: repositoryURL) != nil {
            baseBehindCount = await commitCount(
                range: "\(branch)..\(baseRef)",
                in: repositoryURL
            )
            if baseBehindCount > 0 {
                async let predictedPaths = predictedMergeConflictPaths(
                    currentRef: branch,
                    incomingRef: baseRef,
                    in: repositoryURL
                )
                async let incomingPaths = incomingChangePaths(
                    currentRef: branch,
                    incomingRef: baseRef,
                    in: repositoryURL
                )
                (predictedBaseConflictPaths, baseIncomingChangePaths) = await (
                    predictedPaths,
                    incomingPaths
                )
            }
        }

        let status = CurrentBranchIntegrationStatus(
            branch: branch,
            remote: remote,
            upstreamRef: upstreamRef,
            upstreamBehindCount: upstreamBehindCount,
            baseBranch: baseBranch,
            baseRef: baseRef,
            baseBehindCount: baseBehindCount,
            predictedBaseConflictPaths: predictedBaseConflictPaths,
            baseIncomingChangePaths: baseIncomingChangePaths
        )
        return upstreamBehindCount > 0 || baseBehindCount > 0 ? status : nil
    }

    func fetchCurrentBranchIntegrationRefs(
        _ status: CurrentBranchIntegrationStatus,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async throws {
        var branches: [String] = []
        if let upstreamRef = status.upstreamRef,
           let upstream = Self.remoteBranch(from: upstreamRef),
           upstream.remote == status.remote {
            branches.append(upstream.branch)
        }
        if let baseBranch = status.baseBranch,
           !branches.contains(baseBranch) {
            branches.append(baseBranch)
        }

        for branch in branches {
            try await fetchBranch(
                remote: status.remote,
                branch: branch,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
        }
    }

    private func currentBranchIntegrationRemote(
        upstreamRemote: String?,
        preferredRemote: String?,
        in repositoryURL: URL
    ) async -> String? {
        let availableRemotes = await remotes(in: repositoryURL)
        if let upstreamRemote, availableRemotes.contains(upstreamRemote) {
            return upstreamRemote
        }
        if let preferredRemote, availableRemotes.contains(preferredRemote) {
            return preferredRemote
        }
        if availableRemotes.contains("origin") {
            return "origin"
        }
        return availableRemotes.sorted().first
    }

    private func currentBranchBaseBranch(
        branch: String,
        remote: String,
        gitFlowConfiguration: GitFlowConfiguration,
        in repositoryURL: URL
    ) async -> String? {
        let gitFlowBaseBranch = await MainActor.run { () -> String? in
            let configuration = gitFlowConfiguration.normalized()
            guard configuration.isEnabled,
                  let kind = GitFlowPlanner().topicKind(for: branch, configuration: configuration) else {
                return nil
            }
            return configuration.baseBranch(for: kind)
        }
        if let gitFlowBaseBranch {
            return gitFlowBaseBranch
        }

        guard let remoteDefault = await defaultBranch(in: repositoryURL, remote: remote) else {
            return nil
        }
        let prefix = "\(remote)/"
        return remoteDefault.hasPrefix(prefix)
            ? String(remoteDefault.dropFirst(prefix.count))
            : remoteDefault
    }

    private func commitCount(range: String, in repositoryURL: URL) async -> Int {
        let output = try? await runGit(
            arguments: ["rev-list", "--count", range],
            in: repositoryURL
        )
        return Int(output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    private func predictedMergeConflictPaths(
        currentRef: String,
        incomingRef: String,
        in repositoryURL: URL
    ) async -> Set<String> {
        do {
            _ = try await runGit(
                arguments: [
                    "merge-tree",
                    "--write-tree",
                    "--name-only",
                    "--no-messages",
                    "-z",
                    currentRef,
                    incomingRef
                ],
                in: repositoryURL
            )
            return []
        } catch GitError.commandFailed(let output) {
            return Self.mergeTreeConflictPaths(from: output)
        } catch {
            return []
        }
    }

    private func incomingChangePaths(
        currentRef: String,
        incomingRef: String,
        in repositoryURL: URL
    ) async -> Set<String> {
        guard let output = try? await runGit(
            arguments: [
                "diff",
                "--name-only",
                "-z",
                "\(currentRef)...\(incomingRef)",
                "--"
            ],
            in: repositoryURL
        ) else {
            return []
        }
        return Self.pathList(from: output)
    }

    private func exactConflictPreview(
        for file: StatusFile,
        currentRef: String,
        incomingRef: String?,
        in repositoryURL: URL
    ) async -> (wasPerformed: Bool, blocks: [PotentialConflictBlock]) {
        guard let incomingRef,
              let mergeBase = try? await runGit(
                arguments: ["merge-base", currentRef, incomingRef],
                in: repositoryURL
              ).trimmingCharacters(in: .whitespacesAndNewlines),
              !mergeBase.isEmpty,
              let currentData = await currentFileData(for: file, in: repositoryURL)
        else {
            return (false, [])
        }

        let candidatePaths = [file.path, file.originalPath]
            .compactMap { $0 }
            .reduce(into: [String]()) { paths, path in
                if !paths.contains(path) {
                    paths.append(path)
                }
            }
        let ancestorData = await firstAvailableFileData(
            paths: candidatePaths,
            ref: mergeBase,
            in: repositoryURL
        ) ?? Data()
        let incomingData = await firstAvailableFileData(
            paths: candidatePaths,
            ref: incomingRef,
            in: repositoryURL
        ) ?? Data()

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appending(path: "macgit-potential-conflict-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        } catch {
            return (false, [])
        }
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        let currentURL = temporaryDirectory.appending(path: "current")
        let ancestorURL = temporaryDirectory.appending(path: "ancestor")
        let incomingURL = temporaryDirectory.appending(path: "incoming")
        do {
            try currentData.write(to: currentURL)
            try ancestorData.write(to: ancestorURL)
            try incomingData.write(to: incomingURL)

            _ = try await runGit(
                arguments: [
                    "merge-file",
                    "-p",
                    "--diff3",
                    "-L", "Local changes",
                    "-L", "Merge base",
                    "-L", incomingRef,
                    currentURL.path,
                    ancestorURL.path,
                    incomingURL.path
                ],
                in: repositoryURL
            )
            return (true, [])
        } catch GitError.commandFailed(let output) {
            let blocks = Self.conflictBlocks(from: output, contextLineCount: 0)
            guard !blocks.isEmpty else {
                return (false, [])
            }
            return (true, blocks)
        } catch {
            return (false, [])
        }
    }

    private func currentFileData(for file: StatusFile, in repositoryURL: URL) async -> Data? {
        switch file.status {
        case .staged, .added, .renamed:
            return try? await indexFile(at: file.path, in: repositoryURL)
        case .deleted:
            return Data()
        case .modified, .untracked:
            return try? Data(contentsOf: repositoryURL.appending(path: file.path))
        case .conflict:
            return nil
        }
    }

    private func firstAvailableFileData(
        paths: [String],
        ref: String,
        in repositoryURL: URL
    ) async -> Data? {
        for path in paths {
            if let data = try? await showFile(at: path, ref: ref, in: repositoryURL) {
                return data
            }
        }
        return nil
    }

    nonisolated static func mergeTreeConflictPaths(from output: String) -> Set<String> {
        let components: [Substring]
        if output.contains("\0") {
            components = output.split(separator: "\0", omittingEmptySubsequences: true)
        } else {
            components = output.split(whereSeparator: \.isNewline)
        }

        guard let treeOID = components.first,
              [40, 64].contains(treeOID.count),
              treeOID.allSatisfy(\.isHexDigit)
        else {
            return []
        }

        return Set(components.dropFirst().map(String.init))
    }

    nonisolated static func pathList(from output: String) -> Set<String> {
        if output.contains("\0") {
            return Set(
                output
                    .split(separator: "\0", omittingEmptySubsequences: true)
                    .map(String.init)
            )
        }
        return Set(output.split(whereSeparator: \.isNewline).map(String.init))
    }

    nonisolated static func conflictBlocks(
        from output: String,
        contextLineCount: Int = 3
    ) -> [PotentialConflictBlock] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [PotentialConflictBlock] = []
        var searchIndex = 0

        while searchIndex < lines.count {
            guard let startIndex = lines[searchIndex...].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("<<<<<<<")
            }),
            let endIndex = lines[startIndex...].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(">>>>>>>")
            }) else {
                break
            }

            let lowerBound = max(0, startIndex - contextLineCount)
            let upperBound = min(lines.count - 1, endIndex + contextLineCount)
            var region: PotentialConflictLineRegion = .context
            var blockLines: [PotentialConflictLine] = []

            for lineIndex in lowerBound...upperBound {
                let line = lines[lineIndex]
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                let isMarker: Bool

                if trimmedLine.hasPrefix("<<<<<<<") {
                    region = .local
                    isMarker = true
                } else if trimmedLine.hasPrefix("|||||||") {
                    region = .mergeBase
                    isMarker = true
                } else if trimmedLine.hasPrefix("=======") {
                    region = .incoming
                    isMarker = true
                } else if trimmedLine.hasPrefix(">>>>>>>") {
                    isMarker = true
                } else {
                    isMarker = false
                }

                blockLines.append(
                    PotentialConflictLine(
                        lineNumber: lineIndex + 1,
                        text: line,
                        region: region,
                        isMarker: isMarker
                    )
                )

                if trimmedLine.hasPrefix(">>>>>>>") {
                    region = .context
                }
            }

            blocks.append(PotentialConflictBlock(lines: blockLines))
            searchIndex = endIndex + 1
        }

        return blocks
    }

    private static func remoteName(from ref: String) -> String? {
        remoteBranch(from: ref)?.remote
    }

    private static func remoteBranch(from ref: String) -> (remote: String, branch: String)? {
        let parts = ref.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}
