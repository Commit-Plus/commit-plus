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

enum RepositoryBookmarkProvider: String, Codable {
    case github
    case gitlab
    case bitbucket
    case azureDevOps = "azure"
    case generic
}

struct RepositoryBookmarkIdentity: Equatable {
    var canonicalKey: String
    var provider: RepositoryBookmarkProvider
    var host: String
    var ownerPath: String
    var repositoryName: String
    var canonicalRemoteURL: URL

    var documentID: String {
        Data(canonicalKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func resolve(remoteURLString: String) -> RepositoryBookmarkIdentity? {
        let trimmed = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let azure = AzureReposRemote.parse(trimmed) {
            return RepositoryBookmarkIdentity(
                canonicalKey: "\(AzureReposRemote.host)/\(azure.organization)/\(azure.project)/\(azure.repository)".lowercased(),
                provider: .azureDevOps,
                host: AzureReposRemote.host,
                ownerPath: "\(azure.organization)/\(azure.project)",
                repositoryName: azure.repository,
                canonicalRemoteURL: azure.canonicalURL
            )
        }

        let host: String
        let rawPath: String
        if let scpParts = scpLikeParts(from: trimmed) {
            host = scpParts.host
            rawPath = scpParts.path
        } else {
            guard let url = URL(string: trimmed),
                  let parsedHost = url.host(percentEncoded: false) else {
                return nil
            }
            host = parsedHost
            rawPath = url.path
        }

        let normalizedHost = host.lowercased()
        let pathComponents = rawPath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard pathComponents.count >= 2 else { return nil }

        let rawRepositoryName = pathComponents.last ?? ""
        let repositoryName = rawRepositoryName.lowercased().hasSuffix(".git")
            ? String(rawRepositoryName.dropLast(4))
            : rawRepositoryName
        let ownerComponents = pathComponents.dropLast()
        let ownerPath = ownerComponents.joined(separator: "/")
        guard !repositoryName.isEmpty,
              !ownerPath.isEmpty else {
            return nil
        }

        let normalizedPath = (Array(ownerComponents) + [repositoryName])
            .joined(separator: "/")
            .lowercased()
        guard let canonicalRemoteURL = URL(
            string: "https://\(normalizedHost)/\(ownerPath)/\(repositoryName).git"
        ) else {
            return nil
        }

        return RepositoryBookmarkIdentity(
            canonicalKey: "\(normalizedHost)/\(normalizedPath)",
            provider: provider(for: normalizedHost),
            host: normalizedHost,
            ownerPath: ownerPath,
            repositoryName: repositoryName,
            canonicalRemoteURL: canonicalRemoteURL
        )
    }

    private static func scpLikeParts(from value: String) -> (host: String, path: String)? {
        guard !value.contains("://"),
              let colon = value.firstIndex(of: ":") else {
            return nil
        }
        let hostPart = String(value[..<colon])
        let path = String(value[value.index(after: colon)...])
        let host = hostPart.split(separator: "@").last.map(String.init) ?? hostPart
        guard !host.isEmpty, !path.isEmpty else { return nil }
        return (host, path)
    }

    private static func provider(for host: String) -> RepositoryBookmarkProvider {
        if host == "github.com" || host.contains("github") {
            return .github
        }
        if host == "gitlab.com" || host.contains("gitlab") {
            return .gitlab
        }
        if host == "bitbucket.org" || host.contains("bitbucket") {
            return .bitbucket
        }
        return .generic
    }
}

struct RepositoryBookmark: Codable, Identifiable, Equatable {
    static let schemaVersion = 1

    var id: String
    var canonicalKey: String
    var name: String
    var provider: RepositoryBookmarkProvider
    var host: String
    var ownerPath: String
    var remoteURL: URL
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        canonicalKey: String,
        name: String,
        provider: RepositoryBookmarkProvider,
        host: String,
        ownerPath: String,
        remoteURL: URL,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.canonicalKey = canonicalKey
        self.name = name
        self.provider = provider
        self.host = host
        self.ownerPath = ownerPath
        self.remoteURL = remoteURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(identity: RepositoryBookmarkIdentity, createdAt: Date = Date(), updatedAt: Date = Date()) {
        id = identity.documentID
        canonicalKey = identity.canonicalKey
        name = identity.repositoryName
        provider = identity.provider
        host = identity.host
        ownerPath = identity.ownerPath
        remoteURL = identity.canonicalRemoteURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
