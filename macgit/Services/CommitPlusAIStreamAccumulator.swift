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

/// Deltas are provisional. Only the validated terminal result may authorize tools.
nonisolated struct CommitPlusAIStreamAccumulator {
    private struct ToolDelta: Decodable {
        let index: Int
        let id: String?
        let name: String?
        let argumentsDelta: String
    }
    private struct TextDelta: Decodable { let text: String }
    private var text = ""
    private var tools: [Int: CommitPlusAIToolCall] = [:]
    private var totalBytes = 0

    mutating func append(_ event: CommitPlusAIEventDecoder.Event) throws -> String? {
        totalBytes += event.data.count
        guard totalBytes <= 2_097_152 else { throw CommitPlusAIError.invalidResponse }
        if event.name == "text_delta" {
            let delta = try JSONDecoder().decode(TextDelta.self, from: event.data)
            text += delta.text
            return delta.text
        }
        guard event.name == "tool_call_delta" else { throw CommitPlusAIError.invalidResponse }
        let delta = try JSONDecoder().decode(ToolDelta.self, from: event.data)
        guard delta.index >= 0, delta.index < 64 else { throw CommitPlusAIError.invalidResponse }
        let previous = tools[delta.index]
        let id = delta.id ?? previous?.id ?? ""
        let name = (previous?.name ?? "") + (delta.name ?? "")
        guard previous?.id.isEmpty != false || id == previous?.id else { throw CommitPlusAIError.invalidResponse }
        tools[delta.index] = CommitPlusAIToolCall(id: id, name: name, arguments: (previous?.arguments ?? "") + delta.argumentsDelta)
        return nil
    }

    func validate(_ result: CommitPlusAIResult) throws {
        let accumulated = tools.keys.sorted().compactMap { tools[$0] }
        guard text == result.text, accumulated == result.toolCalls else { throw CommitPlusAIError.invalidResponse }
    }
}
