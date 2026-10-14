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

enum GitBranchNameSanitizer {
    nonisolated static func sanitize(_ input: String) -> String {
        let forbidden = CharacterSet(charactersIn: "~^:?*[\\")
            .union(.controlCharacters)
        var name = input.split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
        name = String(name.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined())
        name = name.replacingOccurrences(of: "@{", with: "-")
        while name.contains("..") {
            name = name.replacingOccurrences(of: "..", with: "-")
        }
        // Branch names are stricter than refs: an initial dash is forbidden.
        while name.hasPrefix("-") || name.hasPrefix("/") { name.removeFirst() }

        // A slash separates ref components; each component has its own rules.
        let components = name.split(separator: "/").compactMap { component -> String? in
            var value = String(component)
            while value.hasPrefix(".") { value.removeFirst() }
            while value.hasSuffix(".lock") { value.removeLast(5) }
            while value.hasSuffix(".") { value.removeLast() }
            return value.isEmpty ? nil : value
        }
        name = components.joined(separator: "/")
        if name.hasPrefix("-") { return sanitize(name) }
        if name == "@" || name == "HEAD" { name += "-branch" }
        return name
    }
}
