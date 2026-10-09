// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated enum DiffTextMetrics {
    static let tabWidth = 4

    static func asciiColumns(_ text: String) -> Int? {
        var columns = 0
        var bytes = text.utf8[...]
        if bytes.last == 0x0D {
            bytes = bytes.dropLast()
        }

        for byte in bytes {
            switch byte {
            case 0x09:
                columns += tabWidth - columns % tabWidth
            case 0x20...0x7E:
                columns += 1
            default:
                return nil
            }
        }
        return columns
    }

    /// Expands tabs to four-column stops and omits a trailing carriage return.
    /// - Precondition: `asciiColumns(text) != nil`.
    static func expandTabs(_ text: String) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(text.utf8.count)

        var bytes = text.utf8[...]
        if bytes.last == 0x0D {
            bytes = bytes.dropLast()
        }

        for byte in bytes {
            if byte == 0x09 {
                output.append(contentsOf: repeatElement(
                    0x20,
                    count: tabWidth - output.count % tabWidth
                ))
            } else {
                output.append(byte)
            }
        }
        return output
    }

    static func displayString(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var column = 0
        var characters = Array(text)
        if characters.last == "\r" {
            characters.removeLast()
        }

        for character in characters {
            if character == "\t" {
                let spaces = tabWidth - column % tabWidth
                result.append(String(repeating: " ", count: spaces))
                column += spaces
            } else {
                result.append(character)
                column += 1
            }
        }
        return result
    }
}
