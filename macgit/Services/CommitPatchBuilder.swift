// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Builds a forward patch from an already direction-oriented Git diff.
/// The existing display parser is deliberately not used: metadata and EOF markers are significant here.
nonisolated enum CommitPatchBuilder {
    static func build(raw: String, selectedLines: Set<CommitPatchRequest.Line>?, reversed: Bool) throws -> String {
        let lines = raw.components(separatedBy: "\n")
        guard lines.filter({ $0.hasPrefix("diff --git ") }).count == 1 else {
            throw failure("Could not isolate the selected file's patch.")
        }
        guard !raw.utf8.contains(0), !lines.contains(where: { $0.hasPrefix("Binary files ") || $0 == "GIT binary patch" }) else {
            throw failure("Binary changes cannot be applied selectively.")
        }
        let metadata = lines.prefix { !$0.hasPrefix("@@ ") }
        guard !metadata.contains(where: {
            ($0.hasPrefix("index ") || $0.contains("file mode ") || $0.hasPrefix("old mode ") || $0.hasPrefix("new mode ")) &&
            ($0.hasSuffix("160000") || $0.hasSuffix("120000"))
        }) else {
            throw failure("Submodule and symbolic-link changes are not supported.")
        }
        guard let selectedLines else { return raw }
        guard !selectedLines.isEmpty else { throw failure("Select at least one changed line.") }
        let wanted = Set(selectedLines.map { reversed ? CommitPatchRequest.Line(old: $0.new, new: $0.old) : $0 })
        var found: Set<CommitPatchRequest.Line> = []
        let firstHunk = lines.firstIndex { $0.hasPrefix("@@ ") } ?? lines.count
        var headers = Array(lines[..<firstHunk]).filter {
            !$0.hasPrefix("index ") && !$0.hasPrefix("similarity index ") &&
                !$0.hasPrefix("old mode ") && !$0.hasPrefix("new mode ")
        }
        var output: [String] = []
        var index = firstHunk
        var delta = 0
        var remainingAfterDeletion = 0
        while index < lines.count, lines[index].hasPrefix("@@ ") {
            let ranges = try ranges(lines[index])
            var old = ranges.oldStart
            var new = ranges.newStart
            var oldCount = 0
            var newCount = 0
            var body: [String] = []
            var changed = false
            var keepMarker = false
            index += 1
            while index < lines.count, !lines[index].hasPrefix("@@ ") {
                let line = lines[index]
                index += 1
                if line.isEmpty && index == lines.count { break }
                if line.hasPrefix("\\ No newline at end of file") {
                    if keepMarker { body.append(line) }
                    continue
                }
                guard let prefix = line.first, [" ", "+", "-"].contains(prefix) else {
                    throw failure("The selected patch has an invalid hunk.")
                }
                keepMarker = true
                switch prefix {
                case " ":
                    body.append(line)
                    old += 1; new += 1; oldCount += 1; newCount += 1
                case "-":
                    let key = CommitPatchRequest.Line(old: old, new: nil)
                    if wanted.contains(key) {
                        body.append(line); found.insert(key); changed = true
                    } else {
                        body.append(" " + line.dropFirst()); newCount += 1
                    }
                    old += 1; oldCount += 1
                default:
                    let key = CommitPatchRequest.Line(old: nil, new: new)
                    if wanted.contains(key) {
                        body.append(line); newCount += 1; found.insert(key); changed = true
                    } else { keepMarker = false }
                    new += 1
                }
            }
            guard old - ranges.oldStart == ranges.oldCount, new - ranges.newStart == ranges.newCount else {
                throw failure("The selected patch has inconsistent line counts.")
            }
            remainingAfterDeletion += newCount
            if changed {
                // Git's zero-length range points BEFORE the insertion, not at its first line.
                let sourceStart = ranges.oldStart
                let targetStart = oldCount == 0 ? sourceStart + delta + 1
                    : (newCount == 0 ? sourceStart + delta - 1 : sourceStart + delta)
                output.append("@@ -\(sourceStart),\(oldCount) +\(max(0, targetStart)),\(newCount) @@")
                output.append(contentsOf: preservingEOF(in: body))
                delta += newCount - oldCount
            }
        }
        guard found == wanted, !output.isEmpty else {
            throw failure("The selected lines no longer match the commit diff. Select them again.")
        }
        // Selecting only some deleted lines leaves a regular file, not /dev/null.
        if headers.contains("+++ /dev/null"), remainingAfterDeletion > 0 {
            guard let source = headers.first(where: { $0.hasPrefix("--- ") }) else {
                throw failure("Missing source path.")
            }
            let path = String(source.dropFirst(4))
            let destination = path.hasPrefix("\"a/") ? "\"b/" + path.dropFirst(3) : "b/" + path.dropFirst(2)
            headers = headers.filter { !$0.hasPrefix("deleted file mode ") }.map {
                $0 == "+++ /dev/null" ? "+++ \(destination)" : $0
            }
        }
        return (headers + output).joined(separator: "\n") + "\n"
    }

    private static func ranges(_ header: String) throws -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        let regex = try NSRegularExpression(pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#)
        guard let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else {
            throw failure("The selected patch has an invalid hunk header.")
        }
        func number(_ group: Int, default fallback: Int = 1) -> Int {
            guard let range = Range(match.range(at: group), in: header) else { return fallback }
            return Int(header[range]) ?? fallback
        }
        return (number(1), number(2), number(3), number(4))
    }

    private static func failure(_ message: String) -> GitError { .commandFailed(message) }

    private static func preservingEOF(in body: [String]) -> [String] {
        var result: [String] = []
        for (index, line) in body.enumerated() {
            // Retaining an old unterminated line before a selected insertion needs a newline on
            // the result side. Express that as a replacement instead of an invalid context line.
            if line.hasPrefix("\\ No newline"), let previous = result.last, previous.hasPrefix(" "),
               body.dropFirst(index + 1).contains(where: { $0.hasPrefix("+") || $0.hasPrefix(" ") }) {
                result.removeLast()
                result += ["-" + previous.dropFirst(), line, "+" + previous.dropFirst()]
            } else { result.append(line) }
        }
        return result
    }
}
