// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class AIThinkingPolicyTests: XCTestCase {
    private func thinkingType(_ parameters: AIThinkingParameters) -> String? {
        (parameters.fields["thinking"] as? [String: Any])?["type"] as? String
    }

    func testClaudeDisablesThinkingTheWayEachModelAccepts() {
        let haiku = AIThinkingPolicy.claude(model: "claude-haiku-5-5", enabled: false, maxTokens: 250)
        XCTAssertEqual(thinkingType(haiku), "disabled")
        XCTAssertEqual(haiku.maxTokens, 250)
        XCTAssertTrue(haiku.allowsForcedToolChoice)

        let sonnet = AIThinkingPolicy.claude(model: "claude-sonnet-5-5", enabled: false, maxTokens: 250)
        XCTAssertEqual(thinkingType(sonnet), "between_tools")
        XCTAssertFalse(sonnet.allowsForcedToolChoice)

        let opus = AIThinkingPolicy.claude(model: "claude-opus-5-5", enabled: false, maxTokens: 250)
        XCTAssertNil(opus.fields["thinking"])
        XCTAssertEqual(opus.effort, "low")
        XCTAssertEqual(opus.maxTokens, 250 + AIThinkingPolicy.minimalReasoningHeadroom)
        XCTAssertFalse(opus.allowsForcedToolChoice)

        let legacy = AIThinkingPolicy.claude(model: "claude-haiku-4-5", enabled: false, maxTokens: 250)
        XCTAssertTrue(legacy.fields.isEmpty)
        XCTAssertTrue(legacy.allowsForcedToolChoice)
    }

    func testClaudeEnablesAdaptiveOrBudgetedThinking() {
        let adaptive = AIThinkingPolicy.claude(model: "claude-haiku-5-5", enabled: true, maxTokens: 250)
        XCTAssertEqual(thinkingType(adaptive), "adaptive")
        XCTAssertEqual(adaptive.maxTokens, 250 + AIThinkingPolicy.thinkingHeadroom)
        XCTAssertFalse(adaptive.allowsForcedToolChoice)

        let legacy = AIThinkingPolicy.claude(model: "claude-haiku-4-5", enabled: true, maxTokens: 250)
        XCTAssertEqual(thinkingType(legacy), "enabled")
        let budget = (legacy.fields["thinking"] as? [String: Any])?["budget_tokens"] as? Int
        XCTAssertEqual(budget, AIThinkingPolicy.legacyClaudeThinkingBudget)
        XCTAssertGreaterThan(legacy.maxTokens, budget ?? .max)
    }

    func testApplyMergesEffortIntoExistingOutputConfig() {
        var body: [String: Any] = ["max_tokens": 250, "output_config": ["format": ["type": "json_schema"]]]
        AIThinkingPolicy.claude(model: "claude-opus-5-5", enabled: false, maxTokens: 250)
            .apply(to: &body, maxTokensKey: "max_tokens")
        let outputConfig = body["output_config"] as? [String: Any]
        XCTAssertEqual(outputConfig?["effort"] as? String, "low")
        XCTAssertNotNil(outputConfig?["format"])
        XCTAssertEqual(body["max_tokens"] as? Int, 250 + AIThinkingPolicy.minimalReasoningHeadroom)
    }

    func testOpenAIOnlySendsReasoningToReasoningModels() {
        XCTAssertTrue(AIThinkingPolicy.openAI(model: "gpt-4o-mini", enabled: true, maxTokens: 250).fields.isEmpty)
        let luna = AIThinkingPolicy.openAI(model: "gpt-6-luna", enabled: false, maxTokens: 250)
        XCTAssertEqual((luna.fields["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        let sol = AIThinkingPolicy.openAI(model: "gpt-6.1-sol", enabled: true, maxTokens: 250)
        XCTAssertEqual((sol.fields["reasoning"] as? [String: Any])?["effort"] as? String, "medium")
    }

    func testGeminiUsesLevelsOrBudgetsByGeneration() {
        let flashOff = AIThinkingPolicy.gemini(model: "gemini-3.5-flash-lite", enabled: false, maxTokens: 512)
        XCTAssertEqual(flashOff.thinkingConfig["thinkingLevel"] as? String, "MINIMAL")
        XCTAssertEqual(flashOff.maxTokens, 512)

        let argonOff = AIThinkingPolicy.gemini(model: "gemini-4-argon", enabled: false, maxTokens: 512)
        XCTAssertEqual(argonOff.thinkingConfig["thinkingLevel"] as? String, "LOW")

        let flashOn = AIThinkingPolicy.gemini(model: "gemini-3.8-flash", enabled: true, maxTokens: 512)
        XCTAssertEqual(flashOn.thinkingConfig["thinkingLevel"] as? String, "HIGH")
        XCTAssertEqual(flashOn.maxTokens, 512 + AIThinkingPolicy.thinkingHeadroom)

        let legacyPro = AIThinkingPolicy.gemini(model: "gemini-2.5-pro", enabled: false, maxTokens: 512)
        XCTAssertEqual(legacyPro.thinkingConfig["thinkingBudget"] as? Int, 128)
        XCTAssertNil(legacyPro.thinkingConfig["thinkingLevel"])
    }

    func testGroqOnlyTouchesReasoningModels() {
        XCTAssertTrue(AIThinkingPolicy.groq(model: "llama-3.3-70b-versatile", enabled: true, maxTokens: 250).fields.isEmpty)
        let gptOSS = AIThinkingPolicy.groq(model: "openai/gpt-oss-20b", enabled: false, maxTokens: 1_024)
        XCTAssertEqual(gptOSS.fields["reasoning_effort"] as? String, "low")
        XCTAssertEqual(gptOSS.fields["include_reasoning"] as? Bool, false)
        let qwen = AIThinkingPolicy.groq(model: "qwen/qwen3.8-27b", enabled: false, maxTokens: 1_024)
        XCTAssertEqual(qwen.fields["reasoning_effort"] as? String, "none")
    }

    func testOpenRouterRespectsEachModelsReasoningCapability() {
        XCTAssertTrue(AIThinkingPolicy.openRouter(capability: nil, enabled: true, maxTokens: 250).fields.isEmpty)

        let optional = OpenRouterReasoningCapability(isMandatory: false, supportedEfforts: ["high", "medium", "low", "none"])
        let optionalOff = AIThinkingPolicy.openRouter(capability: optional, enabled: false, maxTokens: 250)
        XCTAssertEqual((optionalOff.fields["reasoning"] as? [String: Any])?["effort"] as? String, "none")
        XCTAssertEqual(optionalOff.maxTokens, 250)

        let mandatory = OpenRouterReasoningCapability(isMandatory: true, supportedEfforts: ["max", "high", "low"])
        let mandatoryOff = AIThinkingPolicy.openRouter(capability: mandatory, enabled: false, maxTokens: 250)
        XCTAssertEqual((mandatoryOff.fields["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual(mandatoryOff.maxTokens, 250 + AIThinkingPolicy.minimalReasoningHeadroom)

        let mandatoryOn = AIThinkingPolicy.openRouter(capability: mandatory, enabled: true, maxTokens: 250)
        XCTAssertEqual((mandatoryOn.fields["reasoning"] as? [String: Any])?["effort"] as? String, "high")
    }
}
