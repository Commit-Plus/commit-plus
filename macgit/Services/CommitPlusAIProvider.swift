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

struct CommitPlusAIProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .commitPlusAI, displayName: "Commit+ AI", systemImage: "sparkles", detail: "Cloud · Included with Pro",
        dataProcessing: .cloud, billing: .commitPlus, requiresProToConfigureAPIKey: false,
        defaultModel: nil, inputCharacterBudget: 12_000, isImplemented: true
    )
    let client: any CommitPlusAIRequestSending
    let usage: CommitPlusAIUsageController
    let canAccess: @MainActor @Sendable () -> Bool
    var supportsRepositoryAgent: Bool { true }

    func availability() async -> AIProviderAvailability {
        guard await canAccess() else { return .unavailable(CommitPlusAIError.signedOut.localizedDescription) }
        await usage.refresh()
        return await usage.availability
    }
    func generateCommitMessage(request: CommitMessageGenerationRequest) async throws -> GeneratedCommitMessage {
        try await validateAccess()
        let result = try await client.infer(operation: .commitMessage,
            messages: messages(CloudCommitMessagePrompt.jsonInstructions, CloudCommitMessagePrompt.userPrompt(for: request)), structured: true)
        try await validateAccess()
        return try CloudCommitMessageResponse.decode(from: result.text).formatted()
    }
    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> RepositoryAIAnswer {
        try await response(request, onTextDelta: nil)
    }
    func streamRepositoryResponse(request: RepositoryAIRequest, onTextDelta: @escaping @Sendable (String) async -> Void) async throws -> RepositoryAIAnswer {
        try await response(request, onTextDelta: request.requiresStructuredResponse ? nil : onTextDelta)
    }
    private func response(_ request: RepositoryAIRequest, onTextDelta: (@Sendable (String) async -> Void)?) async throws -> RepositoryAIAnswer {
        try await validateAccess()
        let result = try await client.infer(operation: .repositoryResponse,
            messages: messages(RepositoryAIPrompt.instructions(for: request), RepositoryAIPrompt.userPrompt(for: request)),
            structured: request.requiresStructuredResponse, onTextDelta: onTextDelta)
        try await validateAccess()
        return try RepositoryAIAnswerDecoder.decodeProviderText(result.text, requiresStructuredResponse: request.requiresStructuredResponse)
    }
    func generateConflictResolution(request: ConflictAIResolutionRequest) async throws -> ConflictAIResolutionResponse {
        try await validateAccess()
        let context = try ConflictAIPrompt.context(for: request.snapshot, characterBudget: descriptor.inputCharacterBudget)
        let result = try await client.infer(operation: .conflictResolution, messages: messages(ConflictAIPrompt.instructions, context), structured: true)
        try await validateAccess()
        return try ConflictAIResolutionResponse.decode(from: result.text)
    }
    func generateRepositoryAgentTurn(request: RepositoryAIAgentRequest) async throws -> RepositoryAIAgentTurn {
        try await validateAccess()
        var conversation = messages(RepositoryAIPrompt.agentInstructions, RepositoryAIPrompt.agentPrompt(for: request))
        for previous in request.previousToolResults {
            let arguments = try JSONSerialization.data(withJSONObject: ["arguments": previous.toolCall.arguments])
            conversation.append(CommitPlusAIWireMessage(role: "assistant", content: nil, toolCalls: [
                CommitPlusAIToolCall(id: previous.toolCall.id, name: previous.toolCall.name, arguments: String(decoding: arguments, as: UTF8.self))
            ]))
            conversation.append(CommitPlusAIWireMessage(role: "tool", content: previous.commandResult.output, toolCallID: previous.toolCall.id))
        }
        let declarations = RepositoryAIAgentToolSchema.declarations(includingQuickActions: request.isFirstTurn,
            allowsBuiltInWorkflows: request.allowsBuiltInWorkflows, mutationContext: request.mutationContext, remoteOperationContext: request.remoteOperationContext)
        let tools = declarations.map { ["type": "function", "function": $0] as [String: Any] }
        let result = try await client.infer(operation: .repositoryAgent, messages: conversation,
            toolsData: try JSONSerialization.data(withJSONObject: tools), structured: false)
        try await validateAccess()
        let calls = try result.toolCalls.map { call in
            guard let data = call.arguments.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys).isSubset(of: ["arguments"]),
                  object["arguments"] == nil || object["arguments"] is [String],
                  let arguments = RepositoryAIAgentToolSchema.arguments(forToolNamed: call.name, suppliedArguments: object["arguments"] as? [String]) else {
                throw CommitPlusAIError.invalidResponse
            }
            return RepositoryAIAgentToolCall(id: call.id, name: call.name, arguments: arguments)
        }
        return RepositoryAIAgentTurn(text: result.text, toolCalls: calls)
    }
    private func messages(_ system: String, _ user: String) -> [CommitPlusAIWireMessage] {
        [CommitPlusAIWireMessage(role: "system", content: system), CommitPlusAIWireMessage(role: "user", content: user)]
    }
    private func validateAccess() async throws {
        guard await canAccess() else { throw CommitPlusAIError.signedOut }
        try Task.checkCancellation()
    }
}
