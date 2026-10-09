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

nonisolated enum RepositoryAIMutationProposalDecoder {
    static let unsupportedToolName = "unsupported_mutation"
    static let mutationToolNames: Set<String> = [
        "stage_files",
        "unstage_files",
        "create_commit",
        "commit_all_changes",
        "create_branch",
        "checkout_branch",
        "apply_conflict_resolution",
        unsupportedToolName,
    ]

    static func decode(
        toolCall: RepositoryAIAgentToolCall,
        context: RepositoryAIMutationPlanningContext
    ) throws -> RepositoryAIMutationProviderResponse {
        switch toolCall.name {
        case "stage_files":
            let paths = try selectedPaths(
                ids: toolCall.arguments,
                eligible: Set(context.stageablePaths.map(\.id)),
                context: context
            )
            return .proposal(.stageFiles(paths: paths))
        case "unstage_files":
            let paths = try selectedPaths(
                ids: toolCall.arguments,
                eligible: Set(context.unstageablePaths.map(\.id)),
                context: context
            )
            return .proposal(.unstageFiles(paths: paths))
        case "create_commit":
            guard toolCall.arguments.count == 1 else {
                throw RepositoryAIMutationError.invalidProviderResponse("create_commit requires exactly one commit message.")
            }
            return .proposal(.createCommit(message: toolCall.arguments[0]))
        case "commit_all_changes":
            guard toolCall.arguments.isEmpty else {
                throw RepositoryAIMutationError.invalidProviderResponse(
                    "commit_all_changes does not accept model-supplied Git arguments or a commit message."
                )
            }
            return .workflow(.commitAllChanges)
        case "create_branch":
            guard toolCall.arguments.count == 2,
                  let startPoint = context.startPoint(id: toolCall.arguments[1]) else {
                throw RepositoryAIMutationError.invalidProviderResponse(
                    "create_branch requires a branch name and one supplied start-point ID."
                )
            }
            return .proposal(.createBranch(name: toolCall.arguments[0], startPoint: startPoint))
        case "checkout_branch":
            guard toolCall.arguments.count == 1,
                  let branch = context.localBranch(id: toolCall.arguments[0]) else {
                throw RepositoryAIMutationError.invalidProviderResponse(
                    "checkout_branch requires one supplied local-branch ID."
                )
            }
            return .proposal(.checkoutBranch(target: branch))
        case "apply_conflict_resolution":
            guard toolCall.arguments.count == 1,
                  let manifest = context.conflictResolution(id: toolCall.arguments[0]) else {
                throw RepositoryAIMutationError.invalidProviderResponse(
                    "apply_conflict_resolution requires one current app-generated resolution ID."
                )
            }
            return .proposal(.applyConflictResolution(manifest))
        case unsupportedToolName:
            guard toolCall.arguments.count == 1 else {
                throw RepositoryAIMutationError.invalidProviderResponse(
                    "unsupported_mutation requires one user-facing reason."
                )
            }
            let reason = toolCall.arguments[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty, reason.count <= 1_000 else {
                throw RepositoryAIMutationError.invalidProviderResponse(
                    "The unsupported-action explanation is empty or too long."
                )
            }
            return .unsupported(reason: reason)
        default:
            throw RepositoryAIMutationError.invalidProviderResponse("Unknown semantic action \(toolCall.name).")
        }
    }

    private static func selectedPaths(
        ids: [String],
        eligible: Set<String>,
        context: RepositoryAIMutationPlanningContext
    ) throws -> [RepositoryAIMutationPath] {
        guard !ids.isEmpty, Set(ids).count == ids.count else {
            throw RepositoryAIMutationError.invalidProviderResponse(
                "File actions require one or more unique supplied path IDs."
            )
        }
        guard ids.allSatisfy(eligible.contains) else {
            throw RepositoryAIMutationError.invalidProviderResponse(
                "The proposal referenced an unknown or ineligible path ID."
            )
        }
        return try ids.map { id in
            guard let path = context.path(id: id) else {
                throw RepositoryAIMutationError.invalidProviderResponse("Unknown path ID \(id).")
            }
            return path
        }
    }
}

nonisolated enum RepositoryAIMutationPolicy {
    static func validateCommitAllPreparation(
        context: RepositoryAIMutationPlanningContext
    ) throws -> RepositoryAIValidatedMutation {
        guard context.inProgressOperation == nil else {
            throw RepositoryAIMutationError.rejected("Finish the current Git operation before committing all changes.")
        }
        guard context.repositoryState.branch != nil, context.repositoryState.head != "<unborn>" else {
            throw RepositoryAIMutationError.rejected(
                "Repository AI does not commit all changes on a detached or unborn HEAD."
            )
        }
        guard context.author != nil else {
            throw RepositoryAIMutationError.rejected(
                "Configure Git user.name and user.email before committing all changes."
            )
        }
        guard !context.status.staged.contains(where: { $0.status == .conflict }),
              !context.status.unstaged.contains(where: { $0.status == .conflict }) else {
            throw RepositoryAIMutationError.rejected("Resolve all conflicts before committing all changes.")
        }

        let eligiblePathCount = context.status.unstaged.count + context.status.untracked.count
        guard !context.stageablePaths.isEmpty else {
            throw RepositoryAIMutationError.rejected("There are no unstaged or untracked changes to stage.")
        }
        guard context.stageablePaths.count == eligiblePathCount else {
            throw RepositoryAIMutationError.rejected(
                "The complete changed-file manifest is too large to stage automatically. Stage a smaller selection first."
            )
        }
        return try validate(.stageFiles(paths: context.stageablePaths), context: context)
    }

    static func validate(
        _ proposal: RepositoryAIMutationProposal,
        context: RepositoryAIMutationPlanningContext
    ) throws -> RepositoryAIValidatedMutation {
        switch proposal {
        case .stageFiles(let paths):
            try validatePaths(paths)
            guard !paths.isEmpty,
                  paths.allSatisfy({ $0.source == .unstaged || $0.source == .untracked }),
                  paths.allSatisfy({ $0.file.status != .conflict }),
                  paths.allSatisfy(context.stageablePaths.contains) else {
                throw RepositoryAIMutationError.rejected("Only current unstaged or untracked, non-conflicted files can be staged.")
            }
            return validated(
                proposal,
                paths: paths,
                actionState: .stage,
                context: context,
                preview: RepositoryAIMutationPreview(
                    title: "Stage files",
                    confirmationLabel: paths.count == 1 ? "Stage File" : "Stage \(paths.count) Files",
                    summary: "Add exactly the listed working-tree changes to the Git index.",
                    warning: nil,
                    items: previewItems(paths),
                    details: [detail("Result", "Working-tree bytes stay unchanged; the selected content becomes staged.")]
                )
            )
        case .unstageFiles(let paths):
            try validatePaths(paths)
            guard !paths.isEmpty,
                  paths.allSatisfy({ $0.source == .staged && $0.file.status != .conflict }),
                  paths.allSatisfy(context.unstageablePaths.contains) else {
                throw RepositoryAIMutationError.rejected("Only current staged, non-conflicted files can be unstaged.")
            }
            return validated(
                proposal,
                paths: paths,
                actionState: .unstage,
                context: context,
                preview: RepositoryAIMutationPreview(
                    title: "Unstage files",
                    confirmationLabel: paths.count == 1 ? "Unstage File" : "Unstage \(paths.count) Files",
                    summary: "Remove exactly the listed changes from the Git index.",
                    warning: nil,
                    items: previewItems(paths),
                    details: [detail("Result", "Working-tree bytes are preserved; the selected content becomes unstaged.")]
                )
            )
        case .createCommit(let message):
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized == message, !normalized.isEmpty, normalized.count <= 10_000,
                  !normalized.unicodeScalars.contains(where: { $0.value == 0 }) else {
                throw RepositoryAIMutationError.rejected("The commit message must be non-empty, trimmed, and contain no null bytes.")
            }
            guard context.inProgressOperation == nil else {
                throw RepositoryAIMutationError.rejected("Finish the current Git operation before committing.")
            }
            guard context.repositoryState.branch != nil, context.repositoryState.head != "<unborn>" else {
                throw RepositoryAIMutationError.rejected("Repository AI does not create commits on a detached or unborn HEAD.")
            }
            let staged = context.paths.filter { $0.source == .staged }
            guard !staged.isEmpty else {
                throw RepositoryAIMutationError.rejected("The Git index is empty.")
            }
            guard !context.status.staged.contains(where: { $0.status == .conflict }) else {
                throw RepositoryAIMutationError.rejected("Resolve all conflicts before committing.")
            }
            guard let author = context.author else {
                throw RepositoryAIMutationError.rejected("Configure Git user.name and user.email before committing.")
            }
            return validated(
                .createCommit(message: normalized),
                paths: staged,
                actionState: .commit(author: author, signingEnabled: context.signingEnabled),
                context: context,
                preview: RepositoryAIMutationPreview(
                    title: "Create commit",
                    confirmationLabel: "Create Commit",
                    summary: "Create one commit from the current Git index with this exact message:",
                    warning: "Hooks and configured commit signing may run. No unstaged files will be added automatically.",
                    items: [RepositoryAIMutationPreviewItem(id: "message", title: "Commit message", detail: normalized)],
                    details: [
                        detail("Staged files", "\(context.stagedStatistics.fileCount)"),
                        detail(
                            "Statistics",
                            "+\(context.stagedStatistics.additions) −\(context.stagedStatistics.deletions)"
                                + (context.stagedStatistics.binaryFileCount > 0
                                    ? " · \(context.stagedStatistics.binaryFileCount) binary"
                                    : "")
                        ),
                        detail("Author", author),
                        detail("Signing", context.signingEnabled ? "Enabled by Git configuration" : "Not requested by Git configuration"),
                        detail("Result", "HEAD advances by one commit; unstaged changes remain in the working tree."),
                    ]
                )
            )
        case .createBranch(let name, let startPoint):
            guard validBranchName(name) else {
                throw RepositoryAIMutationError.rejected("The proposed local branch name is not valid.")
            }
            guard !context.localBranches.contains(where: { $0.name == name }) else {
                throw RepositoryAIMutationError.rejected("A local branch named \(name) already exists.")
            }
            guard context.startPoints.contains(startPoint) else {
                throw RepositoryAIMutationError.rejected("The start point is not in the current trusted ref manifest.")
            }
            guard context.inProgressOperation == nil else {
                throw RepositoryAIMutationError.rejected("Finish the current Git operation before creating a branch.")
            }
            return validated(
                proposal,
                paths: [],
                actionState: .createBranch(name: name, startPoint: startPoint),
                context: context,
                preview: RepositoryAIMutationPreview(
                    title: "Create local branch",
                    confirmationLabel: "Create Branch",
                    summary: "Create one local branch without checking it out.",
                    warning: nil,
                    items: [
                        detail("New branch", name),
                        detail("Start point", "\(startPoint.name) at \(startPoint.commit.prefix(12))"),
                    ],
                    details: [detail("Result", "The current branch, index, and working tree remain unchanged.")]
                )
            )
        case .checkoutBranch(let target):
            guard let currentBranch = context.repositoryState.branch else {
                throw RepositoryAIMutationError.rejected("Repository AI checkout requires a currently checked-out local branch.")
            }
            guard target.name != currentBranch else {
                throw RepositoryAIMutationError.rejected("\(target.name) is already checked out.")
            }
            guard context.localBranches.contains(target) else {
                throw RepositoryAIMutationError.rejected("The target is not in the current trusted local-branch manifest.")
            }
            guard context.isClean else {
                throw RepositoryAIMutationError.rejected("Commit or stash all working-copy changes before Repository AI checkout.")
            }
            guard context.inProgressOperation == nil else {
                throw RepositoryAIMutationError.rejected("Finish the current Git operation before checking out another branch.")
            }
            guard !context.branchesCheckedOutInOtherWorktrees.contains(target.name) else {
                throw RepositoryAIMutationError.rejected("\(target.name) is already checked out in another worktree.")
            }
            return validated(
                proposal,
                paths: [],
                actionState: .checkoutBranch(previousRef: currentBranch, target: target),
                context: context,
                preview: RepositoryAIMutationPreview(
                    title: "Check out local branch",
                    confirmationLabel: "Check Out \(target.name)",
                    summary: "Switch this clean working copy to an existing local branch.",
                    warning: "The visible files and HEAD will change to match the target branch.",
                    items: [
                        detail("Current branch", currentBranch),
                        detail("Target branch", "\(target.name) at \(target.commit.prefix(12))"),
                    ],
                    details: [detail("Safety check", "The index and working tree are clean, no sequencer is active, and the target is not checked out elsewhere.")]
                )
            )
        case .applyConflictResolution(let manifest):
            guard manifest.repositoryIdentity == context.repositoryIdentity,
                  context.conflictResolutions.contains(manifest),
                  !manifest.files.isEmpty else {
                throw RepositoryAIMutationError.rejected("The conflict resolution is not current for this repository window.")
            }
            let conflicts = manifest.files.map { fileResolution in
                RepositoryAIMutationPath(
                    id: "conflict-\(fileResolution.loadedFile.file.path)",
                    file: fileResolution.loadedFile.file,
                    source: .conflict
                )
            }
            try validatePaths(conflicts)
            let fingerprints = Dictionary(uniqueKeysWithValues: manifest.files.map {
                ($0.loadedFile.file.path, $0.loadedFile.snapshot.fingerprint)
            })
            return validated(
                proposal,
                paths: conflicts,
                actionState: .conflictResolution(id: manifest.id, fingerprints: fingerprints),
                context: context,
                preview: RepositoryAIMutationPreview(
                    title: "Apply AI conflict resolution",
                    confirmationLabel: manifest.files.count == 1 ? "Apply Resolution" : "Apply \(manifest.files.count) Resolutions",
                    summary: "Apply only the selected in-memory resolution generated by Commit+ Conflict AI.",
                    warning: "The listed working-tree files will be replaced with resolved text and staged.",
                    items: previewItems(conflicts),
                    details: [
                        detail("Resolution source", "Commit+ Conflict AI via \(manifest.providerID.rawValue)"),
                        detail("Result", "Resolved files are written to the working tree and added to the index."),
                    ]
                )
            )
        }
    }

    static func isCurrent(
        _ precondition: RepositoryAIMutationPrecondition,
        proposal: RepositoryAIMutationProposal,
        context: RepositoryAIMutationPlanningContext
    ) -> Bool {
        guard precondition.repositoryIdentity == context.repositoryIdentity,
              precondition.repositoryState == context.repositoryState,
              let revalidated = try? validate(proposal, context: context) else { return false }
        return revalidated.precondition == precondition
    }

    private static func validated(
        _ proposal: RepositoryAIMutationProposal,
        paths: [RepositoryAIMutationPath],
        actionState: RepositoryAIMutationActionState,
        context: RepositoryAIMutationPlanningContext,
        preview: RepositoryAIMutationPreview
    ) -> RepositoryAIValidatedMutation {
        RepositoryAIValidatedMutation(
            proposal: proposal,
            preview: preview,
            precondition: RepositoryAIMutationPrecondition(
                repositoryIdentity: context.repositoryIdentity,
                repositoryState: context.repositoryState,
                selectedPaths: paths,
                actionState: actionState
            )
        )
    }

    private static func validatePaths(_ paths: [RepositoryAIMutationPath]) throws {
        guard paths.allSatisfy({ safeRepositoryRelativePath($0.file.path) }) else {
            throw RepositoryAIMutationError.rejected("A selected path is not a canonical repository-relative path.")
        }
        guard paths.allSatisfy({ path in
            guard let originalPath = path.file.originalPath else { return true }
            return safeRepositoryRelativePath(originalPath)
        }) else {
            throw RepositoryAIMutationError.rejected("A rename source is not a canonical repository-relative path.")
        }
    }

    private static func safeRepositoryRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func validBranchName(_ name: String) -> Bool {
        guard name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              name.count <= 255,
              name.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/").contains($0)
              }),
              !name.hasPrefix("-"),
              !name.hasSuffix("."),
              !name.hasSuffix("/"),
              !name.contains(".."),
              !name.contains("//"),
              !name.contains("@{"),
              name != "@",
              !name.split(separator: "/").contains(where: { $0.hasSuffix(".lock") }) else { return false }
        return true
    }

    private static func previewItems(_ paths: [RepositoryAIMutationPath]) -> [RepositoryAIMutationPreviewItem] {
        paths.map { path in
            let rename = path.file.originalPath.map { " (renamed from \($0))" } ?? ""
            return RepositoryAIMutationPreviewItem(
                id: path.id,
                title: path.file.path,
                detail: "\(path.displayStatus)\(rename)"
            )
        }
    }

    private static func detail(_ title: String, _ detail: String) -> RepositoryAIMutationPreviewItem {
        RepositoryAIMutationPreviewItem(id: "\(title)-\(detail)", title: title, detail: detail)
    }
}
