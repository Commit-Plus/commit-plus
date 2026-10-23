// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct AIProviderModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Menu section, such as "Low Cost" or "Most Capable".
    let group: String
}

/// Curated model suggestions shown in Settings → AI.
///
/// IDs were checked against each provider's model documentation (OpenRouter against its
/// public models API) in October 2026. Users can still enter any model ID with "Other…".
enum AIProviderModelCatalog {
    private static let lowCost = "Low Cost"
    private static let balanced = "Balanced"
    private static let mostCapable = "Most Capable"
    private static let popular = "Popular"
    private static let codexModels = "Codex Models"

    static func suggestions(for id: AIProviderID) -> [AIProviderModelOption] {
        switch id {
        case .openAI:
            [
                AIProviderModelOption(id: "gpt-4o-mini", name: "GPT-4o mini", group: lowCost),
                AIProviderModelOption(id: "gpt-6-luna", name: "GPT-6 Luna", group: lowCost),
                AIProviderModelOption(id: "gpt-6.1-sol", name: "GPT-6.1 Sol", group: balanced),
                AIProviderModelOption(id: "gpt-6-astra", name: "GPT-6 Astra", group: mostCapable),
            ]
        case .chatGPTSubscription:
            [
                AIProviderModelOption(id: "gpt-6-luna", name: "GPT-6 Luna", group: lowCost),
                AIProviderModelOption(id: "gpt-6.1-sol", name: "GPT-6.1 Sol", group: balanced),
                AIProviderModelOption(id: "gpt-6-astra", name: "GPT-6 Astra", group: mostCapable),
            ]
        case .chatGPTCodex:
            // The Codex backend has no model list; these are the slugs TablePro ships.
            [
                AIProviderModelOption(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", group: codexModels),
                AIProviderModelOption(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", group: codexModels),
                AIProviderModelOption(id: "gpt-5.5", name: "GPT-5.5", group: codexModels),
            ]
        case .anthropic:
            [
                AIProviderModelOption(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", group: lowCost),
                AIProviderModelOption(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", group: balanced),
                AIProviderModelOption(id: "claude-opus-5-5", name: "Claude Opus 5.5", group: mostCapable),
                AIProviderModelOption(id: "claude-fable-5-1", name: "Claude Fable 5.1", group: mostCapable),
            ]
        case .googleGemini:
            [
                AIProviderModelOption(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite", group: lowCost),
                AIProviderModelOption(id: "gemini-3.1-flash-lite", name: "Gemini 3.1 Flash-Lite", group: lowCost),
                AIProviderModelOption(id: "gemini-3.6-flash", name: "Gemini 3.6 Flash", group: balanced),
                AIProviderModelOption(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", group: balanced),
                AIProviderModelOption(id: "gemini-4-argon", name: "Gemini 4 Argon", group: mostCapable),
            ]
        case .deepSeek:
            [
                AIProviderModelOption(id: "deepseek-flash", name: "DeepSeek V4.1 Flash", group: lowCost),
                AIProviderModelOption(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", group: mostCapable),
            ]
        case .groq:
            [
                AIProviderModelOption(id: "llama-3.1-8b-instant", name: "Llama 3.1 8B Instant", group: lowCost),
                AIProviderModelOption(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B", group: lowCost),
                AIProviderModelOption(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B Versatile", group: balanced),
                AIProviderModelOption(id: "openai/gpt-oss-120b", name: "GPT-OSS 120B", group: balanced),
            ]
        case .openRouter:
            [
                AIProviderModelOption(id: "openrouter/auto", name: "Auto Router", group: popular),
                AIProviderModelOption(id: "anthropic/claude-sonnet-5.5", name: "Claude Sonnet 5.5", group: popular),
                AIProviderModelOption(id: "openai/gpt-6.1-sol", name: "GPT-6.1 Sol", group: popular),
                AIProviderModelOption(id: "google/gemini-3.8-flash", name: "Gemini 3.8 Flash", group: popular),
                AIProviderModelOption(id: "deepseek/deepseek-v4.1-flash", name: "DeepSeek V4.1 Flash", group: popular),
                AIProviderModelOption(id: "x-ai/grok-4.7", name: "Grok 4.7", group: popular),
                AIProviderModelOption(id: "moonshotai/kimi-k3", name: "Kimi K3", group: popular),
                AIProviderModelOption(id: "anthropic/claude-haiku-5.5", name: "Claude Haiku 5.5", group: lowCost),
                AIProviderModelOption(id: "openai/gpt-6-luna", name: "GPT-6 Luna", group: lowCost),
                AIProviderModelOption(id: "z-ai/glm-5.3-flash", name: "GLM 5.3 Flash", group: lowCost),
                AIProviderModelOption(id: "qwen/qwen3.7-flash", name: "Qwen 3.7 Flash", group: lowCost),
                AIProviderModelOption(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B", group: lowCost),
                AIProviderModelOption(id: "mistralai/mistral-nemo", name: "Mistral Nemo", group: lowCost),
            ]
        default:
            []
        }
    }

    /// Friendly name for a model ID, or the ID itself when it is not in the catalog.
    static func displayName(for model: String, provider id: AIProviderID) -> String {
        suggestions(for: id).first { $0.id == model }?.name ?? model
    }

    /// Suggestions grouped for menu sections, in first-appearance order.
    static func groupedSuggestions(for id: AIProviderID) -> [(group: String, options: [AIProviderModelOption])] {
        var groups: [(group: String, options: [AIProviderModelOption])] = []
        for option in suggestions(for: id) {
            if let index = groups.firstIndex(where: { $0.group == option.group }) {
                groups[index].options.append(option)
            } else {
                groups.append((option.group, [option]))
            }
        }
        return groups
    }
}
