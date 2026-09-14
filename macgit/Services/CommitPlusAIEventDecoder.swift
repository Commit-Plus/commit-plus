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

nonisolated struct CommitPlusAIEventDecoder: Sendable {
    struct Event: Sendable { let name: String; let data: Data }
    private var line = Data()
    private var eventName = ""
    private var dataLines: [String] = []
    private var frameBytes = 0

    mutating func append(_ byte: UInt8) throws -> Event? {
        guard line.count < 2_097_152, frameBytes < 2_097_152 else { throw CommitPlusAIError.invalidResponse }
        guard byte == 10 else { line.append(byte); return nil }
        if line.last == 13 { line.removeLast() }
        guard let text = String(data: line, encoding: .utf8) else { throw CommitPlusAIError.invalidResponse }
        frameBytes += line.count
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { eventName = ""; dataLines = []; frameBytes = 0 }
            guard !dataLines.isEmpty else { return nil }
            return Event(name: eventName, data: Data(dataLines.joined(separator: "\n").utf8))
        }
        if text.hasPrefix("event:") { eventName = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        if text.hasPrefix("data:") {
            var value = text.dropFirst(5)
            if value.first == " " { value = value.dropFirst() }
            dataLines.append(String(value))
        }
        return nil
    }
    func finish() throws {
        guard line.isEmpty, dataLines.isEmpty else { throw CommitPlusAIError.invalidResponse }
    }
}
