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

nonisolated struct CommitPlusAIWireMessage: Codable, Sendable {
    let role: String
    let content: String?
    var toolCalls: [CommitPlusAIToolCall]? = nil
    var toolCallID: String? = nil

    private enum CodingKeys: String, CodingKey { case role, content, toolCalls, toolCallID }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let content { try container.encode(content, forKey: .content) }
        else { try container.encodeNil(forKey: .content) }
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }
}

nonisolated struct CommitPlusAIToolCall: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let arguments: String
}

nonisolated enum CommitPlusAIOperation: String, Codable, Sendable {
    case commitMessage = "commit_message"
    case repositoryResponse = "repository_response"
    case repositoryAgent = "repository_agent"
    case conflictResolution = "conflict_resolution"
}

nonisolated struct CommitPlusAIResult: Decodable, Sendable {
    let requestID: String
    let text: String
    let toolCalls: [CommitPlusAIToolCall]
    let allowance: CommitPlusAIAllowance
    let settlement: String

    func validate(requestID expected: String) throws {
        guard requestID.lowercased() == expected.lowercased(), ["settled", "pending"].contains(settlement),
              Set(toolCalls.map(\.id)).count == toolCalls.count else { throw CommitPlusAIError.invalidResponse }
        for call in toolCalls {
            guard !call.id.isEmpty, !call.name.isEmpty,
                  let data = call.arguments.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw CommitPlusAIError.invalidResponse }
        }
    }
}
