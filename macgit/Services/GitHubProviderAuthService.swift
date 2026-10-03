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

protocol GitProviderAuthenticating {
    func requestDeviceAuthorization() async throws -> GitProviderDeviceAuthorization
    func pollDeviceAuthorization(_ authorization: GitProviderDeviceAuthorization) async throws -> GitProviderToken
    func fetchAccount(
        token: GitProviderToken,
        macgitUID: String,
        host: GitProviderHost
    ) async throws -> GitProviderAccount
}

protocol GitProviderHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionGitProviderHTTPClient: GitProviderHTTPClient {
    var session: URLSession = .shared

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitProviderAuthError.invalidResponse
        }
        return (data, response)
    }
}

struct GitHubProviderAuthConfiguration: Equatable {
    var clientID: String
    var scopes: [String]

    static func appConfiguration(bundle: Bundle = .main) -> GitHubProviderAuthConfiguration {
        let configuredClientID = (bundle.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientID = configuredClientID.isEmpty
            ? "Ov23lictC3FXsN0kjsbs"
            : configuredClientID
        return GitHubProviderAuthConfiguration(
            clientID: clientID,
            scopes: ["repo", "read:user", "workflow"]
        )
    }
}

struct GitProviderDeviceAuthorization: Equatable {
    var provider: GitProviderKind = .github
    var deviceCode: String
    var userCode: String
    var verificationURI: URL
    var expiresIn: Int
    var interval: Int
}

enum GitProviderAuthError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidResponse
    case authorizationPending
    case deviceCodeExpired
    case accessDenied
    case slowDown(Int)
    case reauthorizationRequired
    case providerMessage(String)

    static func connectionMessage(_ error: Error) -> String {
        guard let error = error as? URLError else { return error.localizedDescription }
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
            return "Cannot reach the Git server. Check the server URL, network connection, and company VPN."
        case .timedOut: return "The Git server did not respond in time. Check your network or VPN and try again."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .secureConnectionFailed:
            return "Cannot establish a trusted HTTPS connection. Check the server certificate and trust your company's certificate in macOS Keychain."
        default: return error.localizedDescription
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "GitHub account connection is not configured."
        case .invalidResponse:
            "The Git provider returned an invalid response."
        case .authorizationPending:
            "Waiting for GitHub authorization."
        case .deviceCodeExpired:
            "The GitHub device code expired. Try connecting again."
        case .accessDenied:
            "GitHub authorization was cancelled."
        case .slowDown:
            "GitHub asked Commit+ to slow down authorization polling."
        case .reauthorizationRequired:
            "The Git provider account needs to be connected again."
        case .providerMessage(let message):
            message
        }
    }
}

struct GitHubProviderAuthService: GitProviderAuthenticating {
    private let configuration: GitHubProviderAuthConfiguration
    private let httpClient: GitProviderHTTPClient
    private let deviceEndpoint: URL
    private let tokenEndpoint: URL
    private let apiBaseURL: URL
    private let now: () -> Date

    init(
        configuration: GitHubProviderAuthConfiguration,
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        deviceEndpoint: URL = URL(string: "https://github.com/login/device/code")!,
        tokenEndpoint: URL = URL(string: "https://github.com/login/oauth/access_token")!,
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.deviceEndpoint = deviceEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.apiBaseURL = apiBaseURL
        self.now = now
    }

    func requestDeviceAuthorization() async throws -> GitProviderDeviceAuthorization {
        guard !configuration.clientID.isEmpty else {
            throw GitProviderAuthError.invalidConfiguration
        }

        var request = URLRequest(url: deviceEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " "))
        ])

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)
        let payload = try decode(DeviceAuthorizationResponse.self, from: data)
        guard let verificationURI = URL(string: payload.verificationURI) else {
            throw GitProviderAuthError.invalidResponse
        }

        return GitProviderDeviceAuthorization(
            deviceCode: payload.deviceCode,
            userCode: payload.userCode,
            verificationURI: verificationURI,
            expiresIn: payload.expiresIn,
            interval: payload.interval
        )
    }

    func pollDeviceAuthorization(_ authorization: GitProviderDeviceAuthorization) async throws -> GitProviderToken {
        guard !configuration.clientID.isEmpty else {
            throw GitProviderAuthError.invalidConfiguration
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "device_code", value: authorization.deviceCode),
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code")
        ])

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)
        if let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let error = payload.error {
            throw mapDevicePollError(error, interval: authorization.interval, message: payload.errorDescription)
        }
        let payload = try decode(TokenResponse.self, from: data)

        return GitProviderToken(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: payload.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) },
            tokenType: payload.tokenType
        )
    }

    func fetchAccount(
        token: GitProviderToken,
        macgitUID: String,
        host: GitProviderHost
    ) async throws -> GitProviderAccount {
        var request = URLRequest(url: (host.normalized.baseURL == GitProviderHost.githubDotCom.baseURL ? apiBaseURL : host.apiURL).appendingPathComponent("user"))
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)
        let profile = try decode(UserResponse.self, from: data)

        let timestamp = now()
        let normalizedHost = host.normalized.baseURL
        let hostIdentifier = GitProviderHost.accountHostIdentifier(normalizedHost)
        let scopes = response.value(forHTTPHeaderField: "X-OAuth-Scopes")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return GitProviderAccount(
            id: "\(macgitUID):github:\(hostIdentifier):\(profile.id)",
            macgitUID: macgitUID,
            provider: .github,
            hostURL: normalizedHost,
            providerUserID: String(profile.id),
            username: profile.login,
            displayName: profile.name,
            avatarURL: profile.avatarURL,
            scopes: scopes,
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: timestamp,
            lastValidatedAt: timestamp
        )
    }

    private func formEncoded(_ queryItems: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        if response.statusCode == 401 {
            throw GitProviderAuthError.reauthorizationRequired
        }
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw GitProviderAuthError.providerMessage(
                payload?.errorDescription ?? payload?.message ?? "GitHub request failed (HTTP \(response.statusCode))."
            )
        }
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GitProviderAuthError.invalidResponse
        }
    }

    private func mapDevicePollError(_ error: String, interval: Int, message: String?) -> GitProviderAuthError {
        switch error {
        case "authorization_pending":
            return .authorizationPending
        case "slow_down":
            return .slowDown(interval + 5)
        case "expired_token":
            return .deviceCodeExpired
        case "access_denied":
            return .accessDenied
        default:
            return .providerMessage(message ?? "GitHub device authorization failed.")
        }
    }
}

private extension GitHubProviderAuthService {
    struct DeviceAuthorizationResponse: Decodable {
        var deviceCode: String
        var userCode: String
        var verificationURI: String
        var expiresIn: Int
        var interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }

    struct TokenResponse: Decodable {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: Int?
        var tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }

    struct UserResponse: Decodable {
        var id: Int64
        var login: String
        var name: String?
        var avatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case login
            case name
            case avatarURL = "avatar_url"
        }
    }

    struct ErrorResponse: Decodable {
        var error: String?
        var message: String?
        var errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case message
            case errorDescription = "error_description"
        }
    }
}
