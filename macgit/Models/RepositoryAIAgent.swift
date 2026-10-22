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

nonisolated enum RepositoryAIQuickAction: String, CaseIterable, Equatable, Sendable {
    case reviewChanges = "review_changes"
    case explainCommit = "explain_commit"
    case reviewFile = "review_file"
    case compareRefs = "compare_refs"
    case analyzePullRequest = "analyze_pull_request"

    var toolDescription: String {
        switch self {
        case .reviewChanges:
            "Open the guided review for the repository's current staged and working-tree changes."
        case .explainCommit:
            "Open commit selection so the user can choose a commit to explain."
        case .reviewFile:
            "Open changed-file selection so the user can choose one file diff to review."
        case .compareRefs:
            "Open ref selection so the user can choose two branches, tags, or refs to compare."
        case .analyzePullRequest:
            "Open pull-request selection for the current repository."
        }
    }
}

nonisolated struct RepositoryAIGeminiFunctionCallState: Codable, Equatable, Sendable {
    /// The model-owned values that must be replayed unchanged in Gemini's
    /// stateless generateContent function-calling history.
    let callID: String?
    let thoughtSignature: String?
}

nonisolated struct RepositoryAIClaudeThinkingBlock: Codable, Equatable, Sendable {
    /// `thinking` or `redacted_thinking`.
    let type: String
    let thinking: String?
    let signature: String?
    let data: String?
}

nonisolated struct RepositoryAIClaudeToolUseState: Codable, Equatable, Sendable {
    /// The Claude message that issued the call; calls from one message are replayed together.
    let messageID: String
    /// Thinking blocks that preceded the tool use. Claude requires them unchanged,
    /// signatures included, when a tool-use turn continues with thinking enabled.
    let thinkingBlocks: [RepositoryAIClaudeThinkingBlock]
}

nonisolated struct RepositoryAIAgentToolCall: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let arguments: [String]
    let geminiFunctionCallState: RepositoryAIGeminiFunctionCallState?
    let claudeToolUseState: RepositoryAIClaudeToolUseState?

    init(
        id: String,
        name: String,
        arguments: [String],
        geminiFunctionCallState: RepositoryAIGeminiFunctionCallState? = nil,
        claudeToolUseState: RepositoryAIClaudeToolUseState? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.geminiFunctionCallState = geminiFunctionCallState
        self.claudeToolUseState = claudeToolUseState
    }
}

nonisolated struct RepositoryAIAgentToolArgumentsPayload: Decodable, Equatable, Sendable {
    let arguments: [String]?

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let unexpectedKeys = container.allKeys.filter { $0.stringValue != "arguments" }
        guard unexpectedKeys.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Repository AI tool arguments contain unsupported fields."
            ))
        }
        guard let key = DynamicCodingKey(stringValue: "arguments") else {
            arguments = nil
            return
        }
        arguments = try container.decodeIfPresent([String].self, forKey: key)
    }
}

nonisolated struct RepositoryAIAgentTurn: Equatable, Sendable {
    let text: String
    let toolCalls: [RepositoryAIAgentToolCall]
}

nonisolated struct RepositoryAIAgentToolResult: Codable, Equatable, Sendable {
    let toolCall: RepositoryAIAgentToolCall
    let commandResult: RepositoryAIGitCommandResult
}

nonisolated struct RepositoryAIAgentRequest: Sendable {
    let repositoryName: String
    let branchName: String?
    let question: String
    let conversation: [RepositoryAIMessage]
    let previousToolResults: [RepositoryAIAgentToolResult]
    let isFirstTurn: Bool
    let allowsBuiltInWorkflows: Bool
    let mutationContext: RepositoryAIMutationPlanningContext?
    let remoteOperationContext: RepositoryAIRemoteOperationPlanningContext?

    init(
        repositoryName: String,
        branchName: String?,
        question: String,
        conversation: [RepositoryAIMessage],
        previousToolResults: [RepositoryAIAgentToolResult],
        isFirstTurn: Bool,
        allowsBuiltInWorkflows: Bool = true,
        mutationContext: RepositoryAIMutationPlanningContext? = nil,
        remoteOperationContext: RepositoryAIRemoteOperationPlanningContext? = nil
    ) {
        self.repositoryName = repositoryName
        self.branchName = branchName
        self.question = question
        self.conversation = conversation
        self.previousToolResults = previousToolResults
        self.isFirstTurn = isFirstTurn
        self.allowsBuiltInWorkflows = allowsBuiltInWorkflows
        self.mutationContext = mutationContext
        self.remoteOperationContext = remoteOperationContext
    }
}

nonisolated struct RepositoryAIAgentRunResult: Equatable, Sendable {
    let answer: String
    let toolResults: [RepositoryAIAgentToolResult]
    let quickAction: RepositoryAIQuickAction?
    let mutation: RepositoryAIValidatedMutation?
    let mutationWorkflow: RepositoryAIMutationWorkflow?
    let remoteOperation: RepositoryAIValidatedRemoteOperation?

    init(
        answer: String,
        toolResults: [RepositoryAIAgentToolResult],
        quickAction: RepositoryAIQuickAction? = nil,
        mutation: RepositoryAIValidatedMutation? = nil,
        mutationWorkflow: RepositoryAIMutationWorkflow? = nil,
        remoteOperation: RepositoryAIValidatedRemoteOperation? = nil
    ) {
        self.answer = answer
        self.toolResults = toolResults
        self.quickAction = quickAction
        self.mutation = mutation
        self.mutationWorkflow = mutationWorkflow
        self.remoteOperation = remoteOperation
    }
}

nonisolated enum RepositoryAIAgentError: LocalizedError, Equatable {
    case unsupportedTool(String)
    case noRepositoryEvidence
    case tooManyToolCalls
    case emptyResponse
    case unsupportedProvider(String)
    case workflowAccessDenied
    case invalidQuickActionSelection
    case invalidMutationSelection
    case invalidRemoteOperationSelection
    case commandTimedOut
    case requestTimedOut
    case repositoryChanged

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let tool):
            "Repository AI requested an unsupported tool: \(tool)."
        case .noRepositoryEvidence:
            "Repository AI must read repository evidence before answering."
        case .tooManyToolCalls:
            "Repository AI reached its Git query limit. Ask a narrower question."
        case .emptyResponse:
            "The AI provider returned an empty Repository AI response."
        case .unsupportedProvider(let provider):
            "\(provider) does not yet support Repository AI Git tools. Choose a tool-capable provider and try again."
        case .workflowAccessDenied:
            "This built-in Repository AI workflow is unavailable for your plan. You can continue chatting and using Git tools."
        case .invalidQuickActionSelection:
            "Repository AI returned an invalid quick action selection."
        case .invalidMutationSelection:
            "Repository AI can propose only one Git mutation at a time, before running any Git query."
        case .invalidRemoteOperationSelection:
            "Repository AI can propose only one remote Git operation at a time, before running any Git query."
        case .commandTimedOut:
            "A Git query took too long and was stopped. Ask a narrower question."
        case .requestTimedOut:
            "Repository AI took too long to answer. Ask a narrower question and try again."
        case .repositoryChanged:
            "The repository changed while AI was analyzing it. Ask again to use the latest state."
        }
    }
}
