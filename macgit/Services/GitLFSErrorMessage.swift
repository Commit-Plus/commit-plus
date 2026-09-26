// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated enum GitLFSErrorMessage {
    static func sanitized(_ message: String) -> String {
        var result = message
        if let regex = try? NSRegularExpression(pattern: "https?://[^\\s]+") {
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                guard var url = URLComponents(string: String(result[range])) else {
                    result.replaceSubrange(range, with: "<remote URL>")
                    continue
                }
                url.user = nil
                url.password = nil
                url.query = nil
                url.fragment = nil
                result.replaceSubrange(range, with: url.string ?? "<remote URL>")
            }
        }
        result = result.replacingOccurrences(of: "(?i)(authorization[:=]\\s*(?:bearer|basic)\\s+)[^\\s]+", with: "$1<redacted>", options: .regularExpression)
        return String(result.prefix(4000))
    }

    static func describe(_ error: Error) -> String {
        let detail = sanitized(error.localizedDescription)
        let lower = detail.lowercased()
        let explanation: String
        let httpAuthStatus = lower.range(of: #"(?:http(?:/\d(?:\.\d)?)?\s+|status(?: code)?[\s:=]+|error[\s:=]+)(?:401|403)\b|\b(?:401 unauthorized|403 forbidden)\b"#, options: .regularExpression) != nil
        if httpAuthStatus || lower.contains("authentication") || lower.contains("credentials") {
            explanation = "Git LFS could not authenticate. Check the account for the LFS endpoint; it may differ from the Git remote."
        } else if lower.contains("quota") || lower.contains("bandwidth") {
            explanation = "The remote reported a Git LFS storage or bandwidth limit. Check the provider's usage settings."
        } else if lower.contains("no space left") {
            explanation = "There is not enough disk space for Git LFS content."
        } else if lower.contains("could not resolve") || lower.contains("timed out") || lower.contains("network is unreachable") {
            explanation = "Git LFS could not reach the remote. Check the connection and retry."
        } else if lower.contains("object does not exist") || lower.contains("object not found") {
            explanation = "The LFS object is missing from the remote. Its original uploader may need to push the content."
        } else {
            explanation = "Git LFS did not complete. Completed transfers are retained; retry after resolving the issue."
        }
        return explanation + "\n\n" + detail
    }
}
