// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum GitError: LocalizedError {
    case commandFailed(String)
    var errorDescription: String? {
        switch self { case .commandFailed(let message): message }
    }
}

actor GitStatusService {
    func runGit(arguments: [String], in directory: URL) async throws -> String {
        try await runGit(arguments: arguments, in: directory, environment: ProcessInfo.processInfo.environment)
    }

    func runGit(arguments: [String], in directory: URL, environment: [String: String]) async throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var isolatedEnvironment = environment
        isolatedEnvironment["GIT_CONFIG_NOSYSTEM"] = "1"
        isolatedEnvironment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        process.environment = isolatedEnvironment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw GitError.commandFailed(text) }
        return text.trimmingCharacters(in: .newlines)
    }

    func isRebaseInProgress(in repository: URL) async -> Bool {
        for name in ["rebase-merge", "rebase-apply"] {
            if let path = try? await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-path", name], in: repository),
               FileManager.default.fileExists(atPath: path) { return true }
        }
        return false
    }

    func inProgressOperation(in repository: URL) async -> String? {
        if await isRebaseInProgress(in: repository) { return "rebase" }
        for name in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD"] {
            if (try? await runGit(arguments: ["rev-parse", "--verify", name], in: repository)) != nil { return name }
        }
        return nil
    }
}

@main
struct InteractiveRebaseChecks {
    static let git = GitStatusService()

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Rebase ' checks \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for action in [HistoryRebasePlan.Action.reword, .squash, .fixup, .drop, .edit] {
            let repository = try await fixture(root, name: action.rawValue)
            let target = try await commit("HEAD~1", in: repository)
            let originalTree = try await command(["rev-parse", "HEAD^{tree}"], in: repository)
            var plan = try await git.prepareHistoryRebase(commit: target, action: action, in: repository)
            if action == .reword {
                plan.entries[0].message = "Reworded ' message\n\nBody with $HOME and `literal`."
            }
            if action == .squash {
                plan.entries[1].squashMessage = "Combined message\n\nCombined body."
            }
            try await git.executeHistoryRebase(plan, in: repository)
            if action == .edit {
                let paused = await git.isRebaseInProgress(in: repository)
                precondition(paused)
                _ = try await command(["commit", "--amend", "-m", "Edited"], in: repository)
                try await git.resumeHistoryRebase("--continue", in: repository)
            }
            let paused = await git.isRebaseInProgress(in: repository)
            precondition(!paused)
            let subjects = try await command(["log", "--reverse", "--format=%s"], in: repository)
            let count = try await command(["rev-list", "--count", "HEAD"], in: repository)
            precondition(count == ([.squash, .fixup, .drop].contains(action) ? "3" : "4"))
            precondition(subjects.hasSuffix("third"), "Descendant must survive")
            if action == .drop {
                precondition(!FileManager.default.fileExists(atPath: repository.appendingPathComponent("second.txt").path))
            } else {
                let tree = try await command(["rev-parse", "HEAD^{tree}"], in: repository)
                precondition(tree == originalTree)
            }
            if action == .reword {
                let message = try await command(["show", "-s", "--format=%B", "HEAD~1"], in: repository)
                precondition(message == plan.entries[0].message)
            }
            if action == .squash { precondition(subjects.contains("Combined message")) }
            if action == .fixup { precondition(!subjects.contains("second") && subjects.contains("first")) }
            print("PASS: \(action.title), descendants, tree, and quoted paths")
        }
        try await checkGuards(root)
        try await checkPublishedCommitWithMergeParent(root)
        try await checkRootAndReorder(root)
        try await checkConflictRecovery(root)
        try await checkSkippedMessageReplacement(root)
        try await checkEmptyReword(root)
        print("All interactive rebase checks passed.")
    }

    static func checkSkippedMessageReplacement(_ root: URL) async throws {
        for action in [HistoryRebasePlan.Action.reword, .squash] {
            let repository = try await fixture(root, name: "skip-message-" + action.rawValue)
            _ = try await command(["checkout", "-b", "destination", "HEAD~2"], in: repository)
            try "destination".write(to: repository.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
            _ = try await command(["add", "."], in: repository)
            _ = try await command(["commit", "-m", "Destination message"], in: repository)
            let destination = try await commit("HEAD", in: repository)
            _ = try await command(["checkout", "main"], in: repository)
            if action == .squash {
                let replay = try await command(["rev-list", "--reverse", "HEAD~2..HEAD"], in: repository)
                    .split(separator: "\n").map(String.init)
                _ = try await command(["reset", "--hard", "HEAD~2"], in: repository)
                try "prefix".write(to: repository.appendingPathComponent("prefix.txt"), atomically: true, encoding: .utf8)
                _ = try await command(["add", "."], in: repository)
                _ = try await command(["commit", "-m", "Preceding message"], in: repository)
                _ = try await command(["cherry-pick"] + replay, in: repository)
            }
            var plan = try await git.prepareHistoryRebase(commit: destination, in: repository)
            let selectedIndex = action == .squash ? 1 : 0
            plan.entries[selectedIndex].action = action
            if action == .reword {
                plan.entries[0].message = "Must not replace destination message"
            } else {
                plan.entries[1].squashMessage = "Must not replace preceding message"
            }
            try await expectFailure { try await git.executeHistoryRebase(plan, in: repository) }
            let previous = try await commit("HEAD", in: repository)
            try await git.resumeHistoryRebase("--skip", in: repository)
            let restoredParent = try await commit("HEAD~1", in: repository)
            precondition(restoredParent.hash == previous.hash)
            precondition(restoredParent.message == previous.message)
            let tip = try await commit("HEAD", in: repository)
            precondition(tip.message == "third")
            let destinationAfter = try await commit(destination.hash, in: repository)
            precondition(destinationAfter.message == "Destination message")
            let paused = await git.isRebaseInProgress(in: repository)
            precondition(!paused)
            print("PASS: conflict Skip for \(action.title) preserves preceding commit hash and message")
        }
    }

    static func checkEmptyReword(_ root: URL) async throws {
        let repository = try await fixture(root, name: "empty-reword")
        _ = try await command(["commit", "--allow-empty", "-m", "Intentional empty commit"], in: repository)
        let empty = try await commit("HEAD", in: repository)
        let tree = try await command(["rev-parse", "HEAD^{tree}"], in: repository)
        _ = try await command(["commit", "--allow-empty", "-m", "Empty descendant"], in: repository)
        var plan = try await git.prepareHistoryRebase(commit: empty, action: .reword, in: repository)
        plan.entries[0].message = "Reworded empty commit\n\nPreserved body."
        try await git.executeHistoryRebase(plan, in: repository)
        let rewritten = try await commit("HEAD~1", in: repository)
        let message = try await command(["show", "-s", "--format=%B", "HEAD~1"], in: repository)
        precondition(message == plan.entries[0].message)
        precondition(rewritten.parents == empty.parents)
        let newTree = try await command(["rev-parse", "HEAD^{tree}"], in: repository)
        precondition(newTree == tree)
        let count = try await command(["rev-list", "--count", "HEAD"], in: repository)
        precondition(count == "6")
        let descendant = try await commit("HEAD", in: repository)
        precondition(descendant.message == "Empty descendant")
        let paused = await git.isRebaseInProgress(in: repository)
        precondition(!paused)
        print("PASS: reword preserves intentional empty commit, body, tree, parent and empty descendant")
    }

    static func checkGuards(_ root: URL) async throws {
        let repository = try await fixture(root, name: "guards")
        let target = try await commit("HEAD~1", in: repository)
        let plan = try await git.prepareHistoryRebase(commit: target, action: .drop, in: repository)
        try "local".write(to: repository.appendingPathComponent("untracked"), atomically: true, encoding: .utf8)
        try await expectFailure { try await git.executeHistoryRebase(plan, in: repository) }
        try FileManager.default.removeItem(at: repository.appendingPathComponent("untracked"))
        _ = try await command(["commit", "--allow-empty", "-m", "new head"], in: repository)
        try await expectFailure { try await git.executeHistoryRebase(plan, in: repository) }
        _ = try await command(["reset", "--hard", plan.head], in: repository)
        _ = try await command(["checkout", "-b", "same-tip"], in: repository)
        try await expectFailure { try await git.executeHistoryRebase(plan, in: repository) }
        _ = try await command(["checkout", "main"], in: repository)
        _ = try await command(["update-ref", "refs/remotes/origin/main", target.hash], in: repository)
        let availability = try await git.historyRebaseAvailability(in: repository)
        precondition(availability.actions(for: target) == [.reword, .edit, .squash, .fixup, .drop])
        let tip = try await commit("HEAD", in: repository)
        precondition(availability.actions(for: tip) == [.reword, .edit, .squash, .fixup, .drop])
        try await git.executeHistoryRebase(plan, in: repository)
        _ = try await command(["checkout", "--detach"], in: repository)
        try await expectFailure { _ = try await git.prepareHistoryRebase(commit: tip, action: .drop, in: repository) }
        print("PASS: dirty worktree, stale HEAD, published quick actions, detached HEAD")
    }

    static func checkPublishedCommitWithMergeParent(_ root: URL) async throws {
        for action in [HistoryRebasePlan.Action.reword, .edit, .squash, .fixup, .drop] {
            let repository = try await fixture(root, name: "published-merge-parent-" + action.rawValue)
            _ = try await command(["checkout", "-b", "topic", "HEAD~2"], in: repository)
            try "topic".write(to: repository.appendingPathComponent("topic.txt"), atomically: true, encoding: .utf8)
            _ = try await command(["add", "."], in: repository)
            _ = try await command(["commit", "-m", "topic"], in: repository)
            _ = try await command(["checkout", "main"], in: repository)
            _ = try await command(["merge", "--no-ff", "topic", "-m", "Merge topic"], in: repository)
            let merge = try await commit("HEAD", in: repository)
            for name in ["selected", "descendant"] {
                try name.write(to: repository.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
                _ = try await command(["add", "."], in: repository)
                _ = try await command(["commit", "-m", name], in: repository)
            }
            let originalHead = try await command(["rev-parse", "HEAD"], in: repository)
            let originalTree = try await command(["rev-parse", "HEAD^{tree}"], in: repository)
            _ = try await command(["update-ref", "refs/remotes/origin/main", originalHead], in: repository)
            let selected = try await commit("HEAD~1", in: repository)
            let availability = try await git.historyRebaseAvailability(in: repository)
            precondition(availability.actions(for: selected) == [.reword, .edit, .squash, .fixup, .drop])
            precondition(availability.actions(for: merge).isEmpty)
            let topic = try await commit("topic", in: repository)
            let head = try await commit("HEAD", in: repository)
            precondition(availability.isOnCurrentBranch(topic) && !availability.ancestors.contains(topic.hash))
            precondition(!availability.canInteractivelyRebase(to: topic))
            precondition(availability.isOnCurrentBranch(selected) && availability.canInteractivelyRebase(to: selected))
            precondition(availability.isOnCurrentBranch(head) && !availability.canInteractivelyRebase(to: head))
            var plan = try await git.prepareHistoryRebase(commit: selected, action: action, in: repository)
            if action == .squash || action == .fixup {
                precondition(plan.entries[0].commit.isMerge)
                precondition(plan.entries[0].availableActions == [.pick])
                precondition(plan.entries[1].availableActions == HistoryRebasePlan.Action.allCases)
                for unsupportedAction in HistoryRebasePlan.Action.allCases where unsupportedAction != .pick {
                    var invalidPlan = plan
                    invalidPlan.entries[0].action = unsupportedAction
                    precondition(invalidPlan.validationMessage == "Merge-parent commits must keep the Pick action.")
                    try await expectFailure { try await git.executeHistoryRebase(invalidPlan, in: repository) }
                    let unchangedHead = try await command(["rev-parse", "HEAD"], in: repository)
                    precondition(unchangedHead == originalHead)
                    let inProgress = await git.isRebaseInProgress(in: repository)
                    precondition(!inProgress)
                }
                print("PASS: unsupported merge-parent actions rejected before changing repository")
            }
            if action == .reword { plan.entries[0].message = "Reworded published commit" }
            if action == .squash { plan.entries[1].squashMessage = "Squashed into merge" }
            try await git.executeHistoryRebase(plan, in: repository)
            if action == .edit {
                _ = try await command(["commit", "--amend", "-m", "Edited published commit"], in: repository)
                try await git.resumeHistoryRebase("--continue", in: repository)
            }
            let remote = try await command(["rev-parse", "refs/remotes/origin/main"], in: repository)
            precondition(remote == originalHead)
            let descendant = try await commit("HEAD", in: repository)
            precondition(descendant.message == "descendant")
            if action == .drop {
                precondition(!FileManager.default.fileExists(atPath: repository.appendingPathComponent("selected.txt").path))
            } else {
                let tree = try await command(["rev-parse", "HEAD^{tree}"], in: repository)
                precondition(tree == originalTree)
            }
            if action == .squash || action == .fixup {
                let rewrittenMerge = try await commit("HEAD~1", in: repository)
                precondition(rewrittenMerge.parents == merge.parents)
                precondition(rewrittenMerge.message == (action == .squash ? "Squashed into merge" : "Merge topic"))
            }
            print("PASS: published \(action.title) with merge parent, preserved parents/tree/remote ref")
        }
    }

    static func checkRootAndReorder(_ root: URL) async throws {
        let repository = try await fixture(root, name: "root")
        let target = try await commit("HEAD~3", in: repository)
        var rootPlan = try await git.prepareHistoryRebase(commit: target, action: .reword, in: repository)
        rootPlan.entries[0].message = "New root"
        try await git.executeHistoryRebase(rootPlan, in: repository)
        let message = try await command(["show", "-s", "--format=%s", "HEAD~3"], in: repository)
        precondition(message == "New root")
        let base = try await commit("HEAD~3", in: repository)
        var plan = try await git.prepareHistoryRebase(commit: base, in: repository)
        plan.entries.swapAt(0, 1)
        try await git.executeHistoryRebase(plan, in: repository)
        let messages = try await command(["log", "--reverse", "--format=%s"], in: repository)
        precondition(messages == "New root\nsecond\nfirst\nthird")
        var invalid = plan
        invalid.entries[0].action = .squash
        precondition(invalid.validationMessage != nil)
        print("PASS: root reword, interactive reorder, invalid squash")
        let worktree = root.appendingPathComponent("linked worktree")
        _ = try await command(["worktree", "add", "-b", "linked", worktree.path], in: repository)
        let linkedTarget = try await commit("HEAD~1", in: worktree)
        var linkedPlan = try await git.prepareHistoryRebase(commit: linkedTarget, action: .reword, in: worktree)
        linkedPlan.entries[0].message = "Linked worktree message"
        try await git.executeHistoryRebase(linkedPlan, in: worktree)
        let linkedMessage = try await command(["show", "-s", "--format=%s", "HEAD~1"], in: worktree)
        precondition(linkedMessage == "Linked worktree message")
        let mainMessages = try await command(["log", "--reverse", "--format=%s"], in: repository)
        precondition(mainMessages == messages)
        print("PASS: linked worktree isolation")
    }

    static func checkConflictRecovery(_ root: URL) async throws {
        let repository = try await fixture(root, name: "conflict")
        _ = try await command(["checkout", "-b", "other", "HEAD~2"], in: repository)
        try "other".write(to: repository.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
        _ = try await command(["add", "."], in: repository)
        _ = try await command(["commit", "-m", "other"], in: repository)
        let other = try await commit("HEAD", in: repository)
        _ = try await command(["checkout", "main"], in: repository)
        let original = try await command(["rev-parse", "HEAD"], in: repository)
        let plan = try await git.prepareHistoryRebase(commit: other, in: repository)
        try await expectFailure { try await git.executeHistoryRebase(plan, in: repository) }
        let paused = await git.isRebaseInProgress(in: repository)
        precondition(paused)
        try await git.resumeHistoryRebase("--abort", in: repository)
        let restored = try await command(["rev-parse", "HEAD"], in: repository)
        precondition(restored == original)
        var rewordPlan = try await git.prepareHistoryRebase(commit: other, in: repository)
        rewordPlan.entries[0].action = .reword
        rewordPlan.entries[0].message = "Resolved and reworded"
        try await expectFailure { try await git.executeHistoryRebase(rewordPlan, in: repository) }
        try "resolved".write(to: repository.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
        _ = try await command(["add", "."], in: repository)
        try await git.resumeHistoryRebase("--continue", in: repository)
        let subjects = try await command(["log", "--format=%s", "-2"], in: repository)
        precondition(subjects == "third\nResolved and reworded")
        _ = try await command(["reset", "--hard", original], in: repository)
        try await expectFailure { try await git.executeHistoryRebase(plan, in: repository) }
        try await git.resumeHistoryRebase("--skip", in: repository)
        let parent = try await command(["rev-parse", "HEAD^"], in: repository)
        precondition(parent == other.hash)
        _ = try await command(["reset", "--hard", original], in: repository)
        try await expectFailure { _ = try await command(["merge", "--no-ff", "other", "-m", "merge"], in: repository) }
        try "merged".write(to: repository.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
        _ = try await command(["add", "."], in: repository)
        _ = try await command(["commit", "--no-edit"], in: repository)
        let merge = try await commit("HEAD", in: repository)
        let availability = try await git.historyRebaseAvailability(in: repository)
        precondition(availability.actions(for: merge).isEmpty)
        let base = try await commit("HEAD~3", in: repository)
        try await expectFailure { _ = try await git.prepareHistoryRebase(commit: base, in: repository) }
        print("PASS: onto another branch, conflict abort/continue/skip, persistent reword files, merge guards")
    }

    static func fixture(_ root: URL, name: String) async throws -> URL {
        let repository = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try await command(["init", "-b", "main"], in: repository)
        _ = try await command(["config", "user.name", "Rebase Tests"], in: repository)
        _ = try await command(["config", "user.email", "rebase@example.com"], in: repository)
        for name in ["root", "first", "second", "third"] {
            try name.write(to: repository.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
            _ = try await command(["add", "."], in: repository)
            _ = try await command(["commit", "-m", name], in: repository)
        }
        return repository
    }

    static func commit(_ ref: String, in repository: URL) async throws -> Commit {
        let hash = try await command(["rev-parse", ref], in: repository)
        let parents = try await command(["show", "-s", "--format=%P", ref], in: repository)
        let message = try await command(["show", "-s", "--format=%s", ref], in: repository)
        return Commit(hash: hash, parents: parents.split(separator: " ").map(String.init), message: message,
            author: "Tests", email: "rebase@example.com", date: Date(), refs: [])
    }

    static func command(_ arguments: [String], in repository: URL) async throws -> String {
        try await git.runGit(arguments: arguments, in: repository)
    }

    static func expectFailure(_ action: () async throws -> Void) async throws {
        do { try await action() }
        catch { return }
        throw GitError.commandFailed("Expected failure")
    }
}
