// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct HistoryRebasePlan: Identifiable, Sendable {
    enum Action: String, CaseIterable, Identifiable, Sendable {
        case pick, reword, edit, squash, fixup, drop
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pick: "Pick"
            case .reword: "Reword Message"
            case .edit: "Edit"
            case .squash: "Squash into Parent"
            case .fixup: "Fixup into Parent"
            case .drop: "Drop"
            }
        }
    }

    struct Entry: Identifiable, Sendable {
        let commit: Commit
        var action: Action = .pick
        var message: String
        var squashMessage: String = ""
        var id: String { commit.hash }
    }

    let id = UUID()
    let branch: String
    let head: String
    let upstream: String?
    let onto: String?
    let originalHashes: [String]
    let quickAction: Action?
    var entries: [Entry]

    var validationMessage: String? {
        guard Set(entries.map(\.id)) == Set(originalHashes), entries.count == originalHashes.count else {
            return "The commit list changed. Open Interactive Rebase again."
        }
        var hasParent = false
        for entry in entries {
            if entry.action == .drop { continue }
            if entry.action == .squash || entry.action == .fixup {
                if !hasParent { return "Squash and fixup need a preceding commit in this list." }
            }
            if entry.action == .reword && entry.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Enter a commit message for each reword action."
            }
            hasParent = true
        }
        if !hasParent && upstream == nil { return "Keep at least one commit when rewriting from the root." }
        return nil
    }
}
