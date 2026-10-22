// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Request changes for the Settings → AI "Thinking" setting on one request.
struct AIThinkingParameters {
    /// Top-level request fields to add.
    var fields: [String: Any] = [:]
    /// Output-token limit, including room for any thinking the model does.
    var maxTokens: Int
    /// Claude `output_config.effort`, merged into an existing `output_config`.
    var effort: String?
    /// Whether the request may force a tool call (`tool_choice` any/required).
    var allowsForcedToolChoice = true

    /// Applies the limit, fields, and effort to a JSON request body.
    func apply(to body: inout [String: Any], maxTokensKey: String) {
        body[maxTokensKey] = maxTokens
        body.merge(fields) { _, new in new }
        if let effort {
            var outputConfig = body["output_config"] as? [String: Any] ?? [:]
            outputConfig["effort"] = effort
            body["output_config"] = outputConfig
        }
    }
}

/// Reasoning capability of an OpenRouter model, from its public models API.
struct OpenRouterReasoningCapability: Equatable, Sendable {
    var isMandatory: Bool
    var supportedEfforts: [String]
}

/// Maps the global "Thinking" setting onto each provider's request parameters.
///
/// When thinking is on, models that support it think. When it is off, thinking is
/// disabled where the API allows it, or reduced to the lowest effort on models that
/// always reason. Thinking tokens count against the output limit, so the limit grows
/// whenever the model may think.
enum AIThinkingPolicy {
    /// Extra output tokens when thinking is on.
    static let thinkingHeadroom = 4_000
    /// Extra output tokens for models that still reason a little when thinking is off.
    static let minimalReasoningHeadroom = 1_000
    /// Claude `budget_tokens` for models that predate adaptive thinking (minimum 1,024).
    static let legacyClaudeThinkingBudget = 2_048

    // MARK: Claude

    private enum ClaudeThinking {
        /// Thinking cannot be disabled; only effort lowers it.
        case alwaysOn
        /// `disabled` is rejected; `between_tools` turns thinking off.
        case betweenTools
        /// Adaptive thinking that accepts `disabled`.
        case adaptive
        /// Older models: off unless `budget_tokens` is sent.
        case budget
    }

    private static func claudeThinking(for model: String) -> ClaudeThinking {
        if ["claude-fable-5", "claude-mythos-5", "claude-opus-5-5"].contains(where: model.hasPrefix) {
            return .alwaysOn
        }
        if model.hasPrefix("claude-sonnet-5-5") { return .betweenTools }
        let budgetPrefixes = [
            "claude-3", "claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-5",
            "claude-opus-4-1", "claude-opus-4-0", "claude-sonnet-4-0",
            "claude-opus-4-2025", "claude-sonnet-4-2025",
        ]
        if budgetPrefixes.contains(where: model.hasPrefix) { return .budget }
        return .adaptive
    }

    /// Models that reject a forced `tool_choice` regardless of thinking.
    private static func claudeRejectsForcedToolChoice(_ model: String) -> Bool {
        ["claude-fable-5-1", "claude-mythos-5-1", "claude-opus-5-5", "claude-sonnet-5-5"]
            .contains(where: model.hasPrefix)
    }

    static func claude(model: String, enabled: Bool, maxTokens: Int) -> AIThinkingParameters {
        var parameters = AIThinkingParameters(maxTokens: maxTokens)
        switch (claudeThinking(for: model), enabled) {
        case (.alwaysOn, true), (.betweenTools, true), (.adaptive, true):
            parameters.fields = ["thinking": ["type": "adaptive"]]
            parameters.maxTokens += thinkingHeadroom
        case (.alwaysOn, false):
            parameters.effort = "low"
            parameters.maxTokens += minimalReasoningHeadroom
        case (.betweenTools, false):
            parameters.fields = ["thinking": ["type": "between_tools"]]
        case (.adaptive, false):
            parameters.fields = ["thinking": ["type": "disabled"]]
        case (.budget, true):
            parameters.fields = ["thinking": ["type": "enabled", "budget_tokens": legacyClaudeThinkingBudget]]
            parameters.maxTokens += legacyClaudeThinkingBudget
        case (.budget, false):
            break
        }
        // Claude rejects forced tool use while thinking.
        let thinks = enabled || claudeThinking(for: model) == .alwaysOn
        parameters.allowsForcedToolChoice = !thinks && !claudeRejectsForcedToolChoice(model)
        return parameters
    }

    // MARK: OpenAI

    private static func openAIReasons(_ model: String) -> Bool {
        guard !model.contains("-chat") else { return false }
        return ["gpt-5", "gpt-6", "o1", "o3", "o4"].contains(where: model.hasPrefix)
    }

    static func openAI(model: String, enabled: Bool, maxTokens: Int) -> AIThinkingParameters {
        var parameters = AIThinkingParameters(maxTokens: maxTokens)
        guard openAIReasons(model) else { return parameters }
        parameters.fields = ["reasoning": ["effort": enabled ? "medium" : "low"]]
        parameters.maxTokens += enabled ? thinkingHeadroom : minimalReasoningHeadroom
        return parameters
    }

    // MARK: Gemini

    /// Returns the `thinkingConfig` and output limit for a Gemini request.
    static func gemini(model: String, enabled: Bool, maxTokens: Int) -> (thinkingConfig: [String: Any], maxTokens: Int) {
        if model.hasPrefix("gemini-2.5") {
            if enabled {
                return (["thinkingBudget": -1, "includeThoughts": false], maxTokens + thinkingHeadroom)
            }
            // Gemini 2.5 Pro cannot turn thinking off; 128 is its minimum budget.
            let isPro = model.contains("pro")
            return (
                ["thinkingBudget": isPro ? 128 : 0, "includeThoughts": false],
                isPro ? maxTokens + minimalReasoningHeadroom : maxTokens
            )
        }
        if enabled {
            return (["thinkingLevel": "HIGH", "includeThoughts": false], maxTokens + thinkingHeadroom)
        }
        // Pro-class models start at LOW; Flash models offer MINIMAL.
        if model.contains("-pro") || model.contains("argon") {
            return (["thinkingLevel": "LOW", "includeThoughts": false], maxTokens + minimalReasoningHeadroom)
        }
        return (["thinkingLevel": "MINIMAL", "includeThoughts": false], maxTokens)
    }

    // MARK: DeepSeek

    static func deepSeek(enabled: Bool, maxTokens: Int) -> AIThinkingParameters {
        AIThinkingParameters(
            fields: ["thinking": ["type": enabled ? "enabled" : "disabled"]],
            maxTokens: enabled ? maxTokens + thinkingHeadroom : maxTokens
        )
    }

    // MARK: Groq

    static func groq(model: String, enabled: Bool, maxTokens: Int) -> AIThinkingParameters {
        var parameters = AIThinkingParameters(maxTokens: maxTokens)
        if model.hasPrefix("openai/gpt-oss") {
            // GPT-OSS always reasons; effort is the only control.
            parameters.fields = ["reasoning_effort": enabled ? "medium" : "low", "include_reasoning": false]
            parameters.maxTokens += enabled ? thinkingHeadroom : minimalReasoningHeadroom
        } else if model.hasPrefix("qwen/") {
            parameters.fields = enabled ? ["reasoning_format": "hidden"] : ["reasoning_effort": "none"]
            if enabled { parameters.maxTokens += thinkingHeadroom }
        }
        return parameters
    }

    // MARK: OpenRouter

    /// `capability` is `nil` for models without reasoning, or when it is unknown;
    /// then the request is left unchanged.
    static func openRouter(
        capability: OpenRouterReasoningCapability?,
        enabled: Bool,
        maxTokens: Int
    ) -> AIThinkingParameters {
        var parameters = AIThinkingParameters(maxTokens: maxTokens)
        guard let capability, !capability.supportedEfforts.isEmpty else { return parameters }
        let efforts = capability.supportedEfforts
        if enabled {
            let effort = ["medium", "high", "low"].first(where: efforts.contains) ?? efforts[0]
            parameters.fields = ["reasoning": ["effort": effort, "exclude": true]]
            parameters.maxTokens += thinkingHeadroom
        } else if !capability.isMandatory, efforts.contains("none") {
            parameters.fields = ["reasoning": ["effort": "none"]]
        } else if let effort = ["minimal", "low", "medium"].first(where: efforts.contains) {
            parameters.fields = ["reasoning": ["effort": effort, "exclude": true]]
            parameters.maxTokens += minimalReasoningHeadroom
        }
        return parameters
    }
}
