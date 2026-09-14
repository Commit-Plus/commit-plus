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

protocol CommitPlusAIRequestSending: Sendable {
    func send(operation: CommitPlusAIOperation, messages: [CommitPlusAIWireMessage], toolsData: Data,
              structured: Bool, onTextDelta: (@Sendable (String) async -> Void)?) async throws -> CommitPlusAIResult
}

extension CommitPlusAIRequestSending {
    func infer(operation: CommitPlusAIOperation, messages: [CommitPlusAIWireMessage], toolsData: Data = Data("[]".utf8),
               structured: Bool, onTextDelta: (@Sendable (String) async -> Void)? = nil) async throws -> CommitPlusAIResult {
        try await send(operation: operation, messages: messages, toolsData: toolsData, structured: structured, onTextDelta: onTextDelta)
    }
}
