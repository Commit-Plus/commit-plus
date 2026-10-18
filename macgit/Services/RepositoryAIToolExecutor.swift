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

nonisolated protocol RepositoryAIToolExecuting: Sendable {
    func execute(
        _ tool: RepositoryAIToolCall,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> RepositoryAIToolResult

    func fingerprint(
        for tool: RepositoryAIToolCall,
        in repositoryURL: URL
    ) async throws -> String
}

extension GitStatusService: RepositoryAIToolExecuting {
    func execute(
        _ tool: RepositoryAIToolCall,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> RepositoryAIToolResult {
        switch tool {
        case .workingTreeChanges:
            let snapshot: CommitChangeSnapshot
            do {
                snapshot = try await commitChangeSnapshot(
                    in: repositoryURL,
                    source: .workingTree,
                    characterBudget: characterBudget
                )
            } catch CommitMessageGenerationError.noChanges {
                throw RepositoryAIError.noRepositoryData("working tree changes")
            }
            return RepositoryAIToolResult(
                toolName: tool.name,
                title: "Working tree changes",
                fingerprint: snapshot.fingerprint,
                content: snapshot.context,
                isTruncated: snapshot.isTruncated
            )

        case .commitChanges(let reference):
            let hash = try await resolveRepositoryAICommit(reference, in: repositoryURL)
            let metadataBudget = min(1_800, max(400, characterBudget / 5))
            async let metadata = runGit(
                arguments: [
                    "show", "-s",
                    "--format=Commit: %H%nAuthor: %an <%ae>%nDate: %aI%nSubject: %s%n%n%b",
                    hash,
                ],
                in: repositoryURL
            )
            async let nameStatus = runGit(
                arguments: ["show", "--name-status", "--find-renames", "--format=", hash],
                in: repositoryURL
            )
            async let numberStats = runGit(
                arguments: ["show", "--numstat", "--find-renames", "--format=", hash],
                in: repositoryURL
            )
            async let patch = runGit(
                arguments: ["show", "--no-color", "--find-renames", "--format=", "--unified=3", hash],
                in: repositoryURL
            )

            let rawMetadata = try await metadata
            let boundedMetadata = String(rawMetadata.prefix(metadataBudget))
            let changes = CommitMessageContextBuilder.build(
                nameStatus: try await nameStatus,
                numberStats: try await numberStats,
                patch: try await patch,
                characterBudget: max(1_000, characterBudget - boundedMetadata.count - 40)
            )
            let metadataWasTruncated = boundedMetadata.count < rawMetadata.count
            let content = """
                Commit metadata:
                \(boundedMetadata)

                Commit changes:
                \(changes.context)
                """
            return RepositoryAIToolResult(
                toolName: tool.name,
                title: "Commit \(String(hash.prefix(8)))",
                fingerprint: hash,
                content: String(content.prefix(characterBudget)),
                isTruncated: metadataWasTruncated || changes.isTruncated || content.count > characterBudget
            )
        }
    }

    func fingerprint(
        for tool: RepositoryAIToolCall,
        in repositoryURL: URL
    ) async throws -> String {
        switch tool {
        case .workingTreeChanges:
            try await changesFingerprint(in: repositoryURL, source: .workingTree)
        case .commitChanges(let reference):
            try await resolveRepositoryAICommit(reference, in: repositoryURL)
        }
    }

    private func resolveRepositoryAICommit(
        _ reference: String,
        in repositoryURL: URL
    ) async throws -> String {
        let normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._/@{}~^+-]{0,199}$"#,
            options: .regularExpression
        ) != nil else {
            throw RepositoryAIError.invalidCommitReference
        }

        do {
            let output = try await runGit(
                arguments: ["rev-parse", "--verify", "\(normalized)^{commit}"],
                in: repositoryURL
            )
            let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard hash.range(of: #"^[0-9a-fA-F]{40,64}$"#, options: .regularExpression) != nil else {
                throw RepositoryAIError.invalidCommitReference
            }
            return hash
        } catch is RepositoryAIError {
            throw RepositoryAIError.invalidCommitReference
        } catch {
            throw RepositoryAIError.invalidCommitReference
        }
    }
}
