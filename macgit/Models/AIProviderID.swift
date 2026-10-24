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

struct AIProviderID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let commitPlusAI = Self(rawValue: "commit-plus-ai")
    static let appleIntelligence = Self(rawValue: "apple-intelligence")
    static let openAI = Self(rawValue: "openai")
    static let chatGPTSubscription = Self(rawValue: "chatgpt-subscription")
    static let chatGPTCodex = Self(rawValue: "chatgpt-codex")
    static let githubCopilot = Self(rawValue: "github-copilot")
    static let anthropic = Self(rawValue: "anthropic")
    static let googleGemini = Self(rawValue: "google-gemini")
    static let deepSeek = Self(rawValue: "deepseek")
    static let openRouter = Self(rawValue: "openrouter")
    static let groq = Self(rawValue: "groq")
}
