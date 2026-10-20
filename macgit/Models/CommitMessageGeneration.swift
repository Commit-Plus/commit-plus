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

enum CommitChangeSource: Equatable, Sendable {
    case staged
    case workingTree

    var displayName: String {
        switch self {
        case .staged:
            "staged changes"
        case .workingTree:
            "changed files"
        }
    }
}

struct CommitChangeSnapshot: Equatable, Sendable {
    let fingerprint: String
    let context: String
    let isTruncated: Bool
}

struct CommitMessageGenerationRequest: Sendable {
    let repositoryName: String
    let branchName: String?
    let changeSource: CommitChangeSource
    let changes: CommitChangeSnapshot
    let recentCommitSubjects: [String]
}

struct GeneratedCommitMessage: Equatable, Sendable {
    let subject: String
    let body: String?

    var normalized: CommitMessageDraft {
        CommitMessageDraft(subject: subject, body: body ?? "")
    }

    var text: String {
        normalized.message
    }
}

struct CommitMessageDraft: Equatable, Sendable {
    var subject: String
    var body: String

    init(subject: String = "", body: String = "") {
        self.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(message: String) {
        let normalizedMessage = message
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalizedMessage.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        self.init(
            subject: parts.first.map(String.init) ?? "",
            body: parts.count > 1 ? String(parts[1]) : ""
        )
    }

    var message: String {
        let normalized = CommitMessageDraft(subject: subject, body: body)
        guard !normalized.subject.isEmpty else { return normalized.body }
        guard !normalized.body.isEmpty else { return normalized.subject }
        return "\(normalized.subject)\n\n\(normalized.body)"
    }
}

enum CommitMessageGenerationError: LocalizedError, Equatable {
    case noChanges(CommitChangeSource)
    case providerUnavailable(String)
    case providerNotImplemented
    case missingAPIKey(String)
    case providerRequestFailed(String)
    case contextTooLarge
    case invalidResponse
    case changesChanged(CommitChangeSource)

    var errorDescription: String? {
        switch self {
        case .noChanges(let source):
            "No \(source.displayName) are available to generate a commit message."
        case .providerUnavailable(let reason):
            reason
        case .providerNotImplemented:
            "This AI provider is not available yet."
        case .missingAPIKey(let providerName):
            "Add a \(providerName) API key in Settings → AI Providers."
        case .providerRequestFailed(let message):
            message
        case .contextTooLarge:
            "The changes are too large for the selected AI model. Try generating from a smaller change."
        case .invalidResponse:
            "The AI provider did not return a valid commit message."
        case .changesChanged(let source):
            "The \(source.displayName) changed while the message was being generated. Generate it again."
        }
    }
}
