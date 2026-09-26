//
//  GitUndoModels.swift
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
import Combine
import SwiftUI

enum GitUndoResetMode: Equatable {
    case soft
    case mixed
    case hard

    var flag: String {
        switch self {
        case .soft: return "--soft"
        case .mixed: return "--mixed"
        case .hard: return "--hard"
        }
    }
}

indirect enum GitUndoOperation: Equatable {
    case requireCleanWorkingTree
    case requireHead(String)
    case requireLocalBranchTip(name: String, expectedTip: String)
    case requireLocalBranchAbsent(String)
    case stageFiles(paths: [String])
    case unstageFiles(paths: [String])
    case applyPatch(patch: String, cached: Bool, reverse: Bool)
    case checkedWorkingTreePatch(patch: String, reverse: Bool)
    case resetHead(target: String, mode: GitUndoResetMode, expectedHead: String?)
    case commit(message: String, noVerify: Bool, signOff: Bool)
    case cherryPick(commit: String)
    case cherryPickCommits(commits: [String])
    case revert(commit: String)
    case mergeCommit(commit: String, noCommit: Bool, log: Bool)
    case mergeNoFastForward(branch: String, message: String)
    case mergeFastForward(branch: String)
    case rebaseOnto(commit: String)
    case stashPush(message: String, keepIndex: Bool, paths: [String], includeUntracked: Bool)
    case stashApply(ref: String)
    case stashApplyAndDrop(hash: String)
    case stashStore(commit: String, message: String)
    case stashDropMatchingHash(hash: String)
    case checkoutRef(ref: String)
    case createLocalBranch(name: String, startPoint: String, checkout: Bool)
    case deleteLocalBranch(name: String, force: Bool, expectedTip: String?)
    case updateLocalBranch(name: String, newTip: String, expectedTip: String)
    case createTag(name: String, commit: String, annotated: Bool, message: String?)
    case deleteTag(name: String, expectedTarget: String?)
    case renameLocalBranch(from: String, to: String)
    case deleteRemoteBranch(remote: String, branch: String, expectedHash: String)
    case pushBranch(remote: String, localBranch: String, remoteBranch: String)
    case replaceRemoteBranch(BranchForcePushPlan, restoring: Bool)
    case setUpstream(branch: String, upstream: String)
    case sequence([GitUndoOperation])
    case resetHardToHead(expectedHead: String?)
    case stashPop(ref: String)
    case restoreFileSnapshot(id: UUID)
    case deleteFileSnapshot(id: UUID)
    case discardFiles(paths: [String])
    case removeFiles(paths: [String])
    case removeGitFlowWorktree(path: URL, branch: String, expectedTip: String)
    case recreateGitFlowWorktree(path: URL, branch: String, baseTip: String, label: String?)
}

@MainActor
final class OpenRepositoryRegistry {
    static let shared = OpenRepositoryRegistry()

    private var counts: [String: Int] = [:]

    func register(_ repositoryURL: URL) {
        let key = WorktreeLabelStore.key(for: repositoryURL)
        counts[key, default: 0] += 1
    }

    func unregister(_ repositoryURL: URL) {
        let key = WorktreeLabelStore.key(for: repositoryURL)
        guard let count = counts[key] else { return }
        if count <= 1 {
            counts.removeValue(forKey: key)
        } else {
            counts[key] = count - 1
        }
    }

    func isOpen(_ repositoryURL: URL) -> Bool {
        counts[WorktreeLabelStore.key(for: repositoryURL), default: 0] > 0
    }
}

struct GitUndoEntry: Identifiable, Equatable {
    let id: UUID
    let repositoryURL: URL
    let label: String
    let undoOperation: GitUndoOperation
    let redoOperation: GitUndoOperation
    let confirmationMessage: String?

    init(
        id: UUID = UUID(),
        repositoryURL: URL,
        label: String,
        undoOperation: GitUndoOperation,
        redoOperation: GitUndoOperation,
        confirmationMessage: String? = nil
    ) {
        self.id = id
        self.repositoryURL = repositoryURL
        self.label = label
        self.undoOperation = undoOperation
        self.redoOperation = redoOperation
        self.confirmationMessage = confirmationMessage
    }
}

enum GitUndoEntryFactory {
    static func stageFiles(repositoryURL: URL, paths: [String]) -> GitUndoEntry {
        let normalizedPaths = normalized(paths)
        return GitUndoEntry(
            repositoryURL: repositoryURL,
            label: label(verb: "Stage", paths: normalizedPaths),
            undoOperation: .unstageFiles(paths: normalizedPaths),
            redoOperation: .stageFiles(paths: normalizedPaths)
        )
    }

    static func unstageFiles(repositoryURL: URL, paths: [String]) -> GitUndoEntry {
        let normalizedPaths = normalized(paths)
        return GitUndoEntry(
            repositoryURL: repositoryURL,
            label: label(verb: "Unstage", paths: normalizedPaths),
            undoOperation: .stageFiles(paths: normalizedPaths),
            redoOperation: .unstageFiles(paths: normalizedPaths)
        )
    }

    static func applyPatch(
        repositoryURL: URL,
        label: String,
        patch: String,
        cached: Bool,
        reverse: Bool
    ) -> GitUndoEntry {
        GitUndoEntry(
            repositoryURL: repositoryURL,
            label: label,
            undoOperation: .applyPatch(patch: patch, cached: cached, reverse: !reverse),
            redoOperation: .applyPatch(patch: patch, cached: cached, reverse: reverse)
        )
    }

    static func commit(
        repositoryURL: URL,
        oldHead: String,
        newHead: String,
        message: String,
        noVerify: Bool,
        signOff: Bool
    ) -> GitUndoEntry {
        GitUndoEntry(
            repositoryURL: repositoryURL,
            label: "Commit",
            undoOperation: .resetHead(target: oldHead, mode: .soft, expectedHead: newHead),
            redoOperation: .commit(message: message, noVerify: noVerify, signOff: signOff)
        )
    }

    private static func normalized(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for path in paths where !path.isEmpty {
            if seen.insert(path).inserted {
                result.append(path)
            }
        }
        return result
    }

    private static func label(verb: String, paths: [String]) -> String {
        if paths.count == 1, let path = paths.first {
            return "\(verb) \((path as NSString).lastPathComponent)"
        }
        return "\(verb) \(paths.count) files"
    }
}

@MainActor
final class GitUndoManager: ObservableObject {
    @Published private(set) var undoStack: [GitUndoEntry] = []
    @Published private(set) var redoStack: [GitUndoEntry] = []

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var undoTitle: String {
        guard let entry = undoStack.last else { return "Undo Git Action" }
        return "Undo \(entry.label)"
    }

    var redoTitle: String {
        guard let entry = redoStack.last else { return "Redo Git Action" }
        return "Redo \(entry.label)"
    }

    func register(_ entry: GitUndoEntry) {
        undoStack.append(entry)
        redoStack.removeAll()
    }

    func popForUndo() -> GitUndoEntry? {
        undoStack.popLast()
    }

    func completeUndo(_ entry: GitUndoEntry) {
        redoStack.append(entry)
    }

    func restoreUndo(_ entry: GitUndoEntry) {
        undoStack.append(entry)
    }

    func popForRedo() -> GitUndoEntry? {
        redoStack.popLast()
    }

    func completeRedo(_ entry: GitUndoEntry) {
        undoStack.append(entry)
    }

    func restoreRedo(_ entry: GitUndoEntry) {
        redoStack.append(entry)
    }

    func removeAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
