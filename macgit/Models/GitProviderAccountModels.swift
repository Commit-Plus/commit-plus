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

enum GitProviderKind: String, Codable, CaseIterable, Identifiable {
    case github
    case gitlab
    case bitbucket

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .bitbucket: "Bitbucket"
        }
    }
}

struct GitProviderHost: Hashable, Codable {
    var kind: GitProviderKind
    var baseURL: URL

    static let githubDotCom = GitProviderHost(
        kind: .github,
        baseURL: URL(string: "https://github.com")!
    )

    static let gitlabDotCom = GitProviderHost(
        kind: .gitlab,
        baseURL: URL(string: "https://gitlab.com")!
    )

    static let bitbucketDotOrg = GitProviderHost(
        kind: .bitbucket,
        baseURL: URL(string: "https://bitbucket.org")!
    )

    var isSelfHosted: Bool {
        switch kind {
        case .github: return normalized != Self.githubDotCom
        case .gitlab: return normalized != Self.gitlabDotCom
        case .bitbucket: return false
        }
    }

    var apiURL: URL {
        let server = normalized.baseURL
        switch kind {
        case .github:
            return server == Self.githubDotCom.baseURL ? URL(string: "https://api.github.com")! : server.appending(path: "api/v3")
        case .gitlab: return server.appending(path: "api/v4")
        case .bitbucket: return URL(string: "https://api.bitbucket.org/2.0")!
        }
    }

    /// Preserve existing keys for root installations, isolating ports and subpaths.
    static func identityKey(_ url: URL) -> String {
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let port = (url.scheme?.lowercased() == "https" && url.port == 443) ? "" : (url.port.map { ":\($0)" } ?? "")
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return host + port + (path.isEmpty ? "" : "/" + path)
    }

    static func accountHostIdentifier(_ url: URL) -> String {
        identityKey(url).replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "/", with: "%2F")
    }

    static func configured(kind: GitProviderKind, value: String) -> GitProviderHost? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }),
              let url = URL(string: value.contains("://") ? value : "https://" + value),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port == nil || (1...65535).contains(url.port!),
              !url.pathComponents.contains(".."),
              kind != .github || url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty else { return nil }
        return GitProviderHost(kind: kind, baseURL: url).normalized
    }

    var normalized: GitProviderHost {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if components?.scheme == nil {
            components?.scheme = "https"
        }
        let scheme = components?.scheme?.lowercased()
        let hostname = components?.host?.lowercased()
        components?.scheme = scheme
        components?.host = hostname
        if scheme == "https", components?.port == 443 { components?.port = nil }
        components?.user = nil
        components?.password = nil
        let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = path.isEmpty ? "" : "/" + path
        components?.query = nil
        components?.fragment = nil
        return GitProviderHost(kind: kind, baseURL: components?.url ?? baseURL)
    }
}

enum GitProviderTokenStatus: String, Codable, Equatable {
    case valid
    case expired
    case revoked
    case reauthorizationRequired
    case unavailableOnThisDevice
}

enum GitProviderTransportProtocol: String, Codable, Equatable, CaseIterable, Identifiable {
    case https
    case ssh

    var id: String { rawValue }
}

struct GitProviderAccount: Identifiable, Equatable, Codable {
    var id: String
    var macgitUID: String
    var provider: GitProviderKind
    var hostURL: URL
    var providerUserID: String
    var username: String
    var displayName: String?
    var avatarURL: URL?
    var scopes: [String]
    var permissions: [String: String]
    var tokenStatus: GitProviderTokenStatus
    var transportProtocol: GitProviderTransportProtocol
    var connectedAt: Date
    var lastValidatedAt: Date?

    init(
        id: String,
        macgitUID: String,
        provider: GitProviderKind,
        hostURL: URL,
        providerUserID: String,
        username: String,
        displayName: String?,
        avatarURL: URL?,
        scopes: [String],
        permissions: [String: String],
        tokenStatus: GitProviderTokenStatus,
        transportProtocol: GitProviderTransportProtocol = .https,
        connectedAt: Date,
        lastValidatedAt: Date?
    ) {
        self.id = id
        self.macgitUID = macgitUID
        self.provider = provider
        self.hostURL = hostURL
        self.providerUserID = providerUserID
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.scopes = scopes
        self.permissions = permissions
        self.tokenStatus = tokenStatus
        self.transportProtocol = transportProtocol
        self.connectedAt = connectedAt
        self.lastValidatedAt = lastValidatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case macgitUID
        case provider
        case hostURL
        case providerUserID
        case username
        case displayName
        case avatarURL
        case scopes
        case permissions
        case tokenStatus
        case transportProtocol
        case connectedAt
        case lastValidatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        macgitUID = try container.decode(String.self, forKey: .macgitUID)
        provider = try container.decode(GitProviderKind.self, forKey: .provider)
        hostURL = try container.decode(URL.self, forKey: .hostURL)
        providerUserID = try container.decode(String.self, forKey: .providerUserID)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        scopes = try container.decode([String].self, forKey: .scopes)
        permissions = try container.decode([String: String].self, forKey: .permissions)
        tokenStatus = try container.decode(GitProviderTokenStatus.self, forKey: .tokenStatus)
        transportProtocol = try container.decodeIfPresent(
            GitProviderTransportProtocol.self,
            forKey: .transportProtocol
        ) ?? .https
        connectedAt = try container.decode(Date.self, forKey: .connectedAt)
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
    }
}

struct GitProviderToken: Equatable, Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var tokenType: String
}

struct GitRepositoryIdentity: Equatable, Codable {
    var provider: GitProviderKind
    var hostURL: URL
    var owner: String
    var name: String
}
