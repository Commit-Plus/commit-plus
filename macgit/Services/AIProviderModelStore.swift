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

protocol AIProviderModelStore: Sendable {
    func customModel(for providerID: AIProviderID) -> String?
    func saveCustomModel(_ model: String, for providerID: AIProviderID)
    func resetModel(for providerID: AIProviderID)
    /// The Settings → AI "Thinking" setting, shared by every provider.
    var isThinkingEnabled: Bool { get }
    func setThinkingEnabled(_ isEnabled: Bool)
}

extension AIProviderModelStore {
    func model(for descriptor: AIProviderDescriptor) -> String? {
        customModel(for: descriptor.id) ?? descriptor.defaultModel
    }

    var isThinkingEnabled: Bool { false }
    func setThinkingEnabled(_ isEnabled: Bool) {}
}

final class UserDefaultsAIProviderModelStore: AIProviderModelStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix = "ai.commitMessage.modelOverride."
    private let thinkingKey = "ai.thinkingEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func customModel(for providerID: AIProviderID) -> String? {
        guard let stored = defaults.string(forKey: key(for: providerID)) else { return nil }
        let normalized = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func saveCustomModel(_ model: String, for providerID: AIProviderID) {
        defaults.set(model, forKey: key(for: providerID))
    }

    func resetModel(for providerID: AIProviderID) {
        defaults.removeObject(forKey: key(for: providerID))
    }

    var isThinkingEnabled: Bool {
        defaults.bool(forKey: thinkingKey)
    }

    func setThinkingEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: thinkingKey)
    }

    private func key(for providerID: AIProviderID) -> String {
        keyPrefix + providerID.rawValue
    }
}
