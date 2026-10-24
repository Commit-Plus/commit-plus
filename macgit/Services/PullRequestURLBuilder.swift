//
//  PullRequestURLBuilder.swift
//  macgit
//

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

enum PullRequestURLBuilder {
    static func build(remoteURL: String, branch: String) -> URL? {
        let trimmedBranch = branch.trimmingCharacters(in: .whitespaces)
        guard !trimmedBranch.isEmpty else { return nil }
        if let azure = AzureReposRemote.parse(remoteURL) {
            return azure.pullRequestCreateURL(sourceBranch: trimmedBranch)
        }
        guard let base = normalize(remoteURL: remoteURL) else { return nil }
        return buildURL(base: base, branch: trimmedBranch)
    }

    static func canBuild(remoteURL: String) -> Bool {
        if AzureReposRemote.parse(remoteURL) != nil { return true }
        guard let base = normalize(remoteURL: remoteURL) else { return false }
        return hostProvider(base.host) != nil
    }

    private enum Provider {
        case github
        case gitlab
        case bitbucket
    }

    private struct Normalized {
        let host: String
        let pathComponents: [String]
    }

    private static func normalize(remoteURL: String) -> Normalized? {
        var cleaned = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }

        if cleaned.hasPrefix("git@") {
            let withoutPrefix = cleaned.dropFirst("git@".count)
            guard let colonIndex = withoutPrefix.firstIndex(of: ":") else { return nil }
            let host = String(withoutPrefix[..<colonIndex])
            let path = String(withoutPrefix[withoutPrefix.index(after: colonIndex)...])
            cleaned = "https://\(host)/\(path)"
        } else if cleaned.hasPrefix("ssh://") {
            cleaned = String(cleaned.dropFirst("ssh://".count))
            if cleaned.hasPrefix("git@") {
                cleaned = String(cleaned.dropFirst("git@".count))
            }
            if let slashIndex = cleaned.firstIndex(of: "/") {
                let hostPart = String(cleaned[cleaned.startIndex...slashIndex])
                    .replacingOccurrences(of: ":", with: "")
                let pathPart = String(cleaned[cleaned.index(after: slashIndex)...])
                cleaned = "https://" + hostPart + pathPart
            } else {
                cleaned = "https://\(cleaned)"
            }
        }

        guard let url = URL(string: cleaned),
              let host = url.host,
              !host.isEmpty
        else { return nil }
        let components = url.path
            .split(separator: "/")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".git") ? String($0.dropLast(".git".count)) : $0 }
            .filter { !$0.isEmpty }
        guard components.count >= 2 else { return nil }
        return Normalized(host: host.lowercased(), pathComponents: components)
    }

    private static func hostProvider(_ host: String) -> Provider? {
        if host.contains("github") { return .github }
        if host.contains("gitlab") { return .gitlab }
        if host.contains("bitbucket") { return .bitbucket }
        return nil
    }

    private static func buildURL(base: Normalized, branch: String) -> URL? {
        guard let provider = hostProvider(base.host) else { return nil }
        let escaped = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch
        switch provider {
        case .github:
            guard let owner = base.pathComponents.first,
                  let repo = base.pathComponents.dropFirst().first
            else { return nil }
            return URL(string: "https://\(base.host)/\(owner)/\(repo)/compare/\(escaped)?expand=1")
        case .gitlab:
            // GitLab supports nested groups: join all but the last as the
            // "namespace" and the last as the project.
            guard base.pathComponents.count >= 2 else { return nil }
            let namespace = base.pathComponents.dropLast().joined(separator: "/")
            let project = base.pathComponents.last ?? ""
            return URL(string: "https://\(base.host)/\(namespace)/\(project)/-/merge_requests/new?merge_request[source_branch]=\(escaped)")
        case .bitbucket:
            guard let owner = base.pathComponents.first,
                  let repo = base.pathComponents.dropFirst().first
            else { return nil }
            return URL(string: "https://\(base.host)/\(owner)/\(repo)/pull-requests/new?source=\(escaped)")
        }
    }
}
