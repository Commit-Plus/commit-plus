//
//  GitBranchUndoSupport.swift
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

struct GitBranchUndoSupport {
    private let runner: any GitCommandRunning

    init(runner: (any GitCommandRunning)? = nil) {
        self.runner = runner ?? GitStatusService.shared
    }

    func currentRef(in repositoryURL: URL) async throws -> String {
        let branch = try await runner.runGit(arguments: ["branch", "--show-current"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }

        return try await runner.runGit(arguments: ["rev-parse", "HEAD"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func tip(of ref: String, in repositoryURL: URL) async throws -> String {
        try await runner.runGit(arguments: ["rev-parse", "\(ref)^{commit}"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func upstream(of branch: String, in repositoryURL: URL) async -> String? {
        let output = try? await runner.runGit(
            arguments: ["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"],
            in: repositoryURL
        )
        let upstream = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        return upstream?.isEmpty == false ? upstream : nil
    }

    /// Undo recreates the local branch (and its upstream), plus the remote branch when it was deleted too.
    static func deletedBranchUndoEntry(
        repositoryURL: URL,
        branch: String,
        force: Bool,
        tip: String,
        upstream: String?,
        remoteTarget: RemoteBranchDeleteTarget?,
        remoteHash: String?
    ) -> GitUndoEntry {
        var undoOperations: [GitUndoOperation] = [
            .createLocalBranch(name: branch, startPoint: tip, checkout: false)
        ]
        // Restore the remote first: the upstream may be the remote-tracking ref it recreates.
        if let remoteTarget, let remoteHash {
            undoOperations.append(
                .pushBranch(
                    remote: remoteTarget.remote,
                    localBranch: remoteHash,
                    remoteBranch: "refs/heads/\(remoteTarget.branch)"
                )
            )
        }
        if let upstream {
            undoOperations.append(.setUpstream(branch: branch, upstream: upstream))
        }

        var redoOperations: [GitUndoOperation] = [
            .deleteLocalBranch(name: branch, force: force, expectedTip: tip)
        ]
        if let remoteTarget, let remoteHash {
            redoOperations.append(
                .deleteRemoteBranch(
                    remote: remoteTarget.remote,
                    branch: remoteTarget.branch,
                    expectedHash: remoteHash
                )
            )
        }
        return GitUndoEntry(
            repositoryURL: repositoryURL,
            label: "Delete branch \(branch)",
            undoOperation: .sequence(undoOperations),
            redoOperation: .sequence(redoOperations)
        )
    }
}
