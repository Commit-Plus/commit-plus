// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct GitHubNotification: Codable, Identifiable, Equatable {
    struct Subject: Codable, Equatable {
        var title: String
        var url: URL?
        var type: String
    }
    struct Repository: Codable, Equatable {
        var fullName: String
        var htmlURL: URL
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name", htmlURL = "html_url"
        }
    }
    var id: String
    var subject: Subject
    var repository: Repository
    var reason: String
    var unread: Bool
    var updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, subject, repository, reason, unread
        case updatedAt = "updated_at"
    }

    /// API URLs are never opened in the browser or requested with credentials.
    /// Only construct known web routes on the connected account's host.
    func webURL(account: GitProviderAccount) -> URL {
        let base = account.hostURL.appending(path: repository.fullName)
        guard let url = subject.url else { return base }
        let parts = url.pathComponents
        guard let marker = parts.firstIndex(of: "repos"), parts.count > marker + 4 else { return base }
        let kind = parts[marker + 3]
        let number = parts[marker + 4]
        switch kind {
        case "issues": return base.appending(path: "issues/\(number)")
        case "pulls": return base.appending(path: "pull/\(number)")
        case "commits": return base.appending(path: "commit/\(number)")
        default: return base
        }
    }
}
