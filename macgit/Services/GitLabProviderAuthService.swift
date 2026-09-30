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

struct GitLabProviderAuthConfiguration: Equatable {
    var clientID: String
    var redirectURI: URL
    var scopes: [String]

    static func appConfiguration(bundle: Bundle = .main) -> GitLabProviderAuthConfiguration {
        let configuredClientID = (bundle.object(forInfoDictionaryKey: "GitLabOAuthClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GitLabProviderAuthConfiguration(
            clientID: configuredClientID,
            redirectURI: URL(string: "macgit://git-provider/oauth/callback")!,
            scopes: ["api", "read_user", "write_repository"]
        )
    }
}

protocol GitLabProviderOAuthAuthenticating {
    func requestDeviceAuthorization(host: GitProviderHost) async throws -> GitProviderDeviceAuthorization
    func pollDeviceAuthorization(
        _ authorization: GitProviderDeviceAuthorization,
        host: GitProviderHost
    ) async throws -> GitProviderToken
    func authorizationURL(for session: GitProviderOAuthSession) throws -> URL
    func exchangeCallback(
        _ callback: GitProviderOAuthCallback,
        session: GitProviderOAuthSession
    ) async throws -> GitProviderToken
    func refreshToken(
        _ refreshToken: String,
        host: GitProviderHost
    ) async throws -> GitProviderToken
    func fetchAccount(
        token: GitProviderToken,
        macgitUID: String,
        host: GitProviderHost
    ) async throws -> GitProviderAccount
}

struct GitLabProviderAuthService: GitLabProviderOAuthAuthenticating {
    private let configuration: GitLabProviderAuthConfiguration
    private let httpClient: GitProviderHTTPClient
    private let now: () -> Date

    init(
        configuration: GitLabProviderAuthConfiguration,
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.now = now
    }

    func requestDeviceAuthorization(host: GitProviderHost) async throws -> GitProviderDeviceAuthorization {
        guard !configuration.clientID.isEmpty else {
            throw GitProviderAuthError.invalidConfiguration
        }

        var request = URLRequest(
            url: host.normalized.baseURL
                .appendingPathComponent("oauth")
                .appendingPathComponent("authorize_device")
        )
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
        let verificationURIString = payload.verificationURIComplete ?? payload.verificationURI
        guard let verificationURI = URL(string: verificationURIString) else {
            throw GitProviderAuthError.invalidResponse
        }

        return GitProviderDeviceAuthorization(
            provider: .gitlab,
            deviceCode: payload.deviceCode,
            userCode: payload.userCode,
            verificationURI: verificationURI,
            expiresIn: payload.expiresIn,
            interval: payload.interval
        )
    }

    func pollDeviceAuthorization(
        _ authorization: GitProviderDeviceAuthorization,
        host: GitProviderHost
    ) async throws -> GitProviderToken {
        guard !configuration.clientID.isEmpty else {
            throw GitProviderAuthError.invalidConfiguration
        }

        var request = URLRequest(
            url: host.normalized.baseURL
                .appendingPathComponent("oauth")
                .appendingPathComponent("token")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "device_code", value: authorization.deviceCode),
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code")
        ])

        let (data, response) = try await httpClient.data(for: request)
        if let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let error = payload.error {
            throw mapDevicePollError(error, interval: authorization.interval, message: payload.errorDescription)
        }
        try validate(response: response, data: data)

        let payload = try decode(TokenResponse.self, from: data)
        return GitProviderToken(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: payload.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) },
            tokenType: payload.tokenType
        )
    }

    func authorizationURL(for session: GitProviderOAuthSession) throws -> URL {
        guard session.provider == .gitlab,
              !configuration.clientID.isEmpty else {
            throw GitProviderAuthError.invalidConfiguration
        }

        let baseURL = session.host.normalized.baseURL
        var components = URLComponents(
            url: baseURL.appendingPathComponent("oauth").appendingPathComponent("authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: session.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: session.state),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: GitProviderPKCE.challenge(for: session.codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else {
            throw GitProviderAuthError.invalidResponse
        }
        return url
    }

    func exchangeCallback(
        _ callback: GitProviderOAuthCallback,
        session: GitProviderOAuthSession
    ) async throws -> GitProviderToken {
        guard callback.state == session.state else {
            throw GitProviderOAuthError.stateMismatch
        }
        guard session.provider == .gitlab,
              !configuration.clientID.isEmpty else {
            throw GitProviderAuthError.invalidConfiguration
        }

        var request = URLRequest(
            url: session.host.normalized.baseURL
                .appendingPathComponent("oauth")
                .appendingPathComponent("token")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: callback.code),
            URLQueryItem(name: "redirect_uri", value: session.redirectURI.absoluteString),
            URLQueryItem(name: "code_verifier", value: session.codeVerifier),
        ])

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)
        let payload = try decode(TokenResponse.self, from: data)
        return GitProviderToken(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: payload.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) },
            tokenType: payload.tokenType
        )
    }

    func refreshToken(
        _ refreshToken: String,
        host: GitProviderHost
    ) async throws -> GitProviderToken {
        guard !configuration.clientID.isEmpty else {
            throw GitProviderAuthError.invalidConfiguration
        }

        var request = URLRequest(
            url: host.normalized.baseURL
                .appendingPathComponent("oauth")
                .appendingPathComponent("token")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
        ])

        let (data, response) = try await httpClient.data(for: request)
        if let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           payload.error == "invalid_grant" {
            throw GitProviderAuthError.reauthorizationRequired
        }
        try validate(response: response, data: data, unauthorizedMeansReauthorization: true)
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
        let normalizedHost = host.normalized
        var request = URLRequest(
            url: normalizedHost.baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("v4")
                .appendingPathComponent("user")
        )
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data, unauthorizedMeansReauthorization: true)
        let profile = try decode(UserResponse.self, from: data)
        let timestamp = now()
        let hostIdentifier = normalizedHost.baseURL.host(percentEncoded: false)?.lowercased()
            ?? normalizedHost.baseURL.absoluteString.lowercased()

        return GitProviderAccount(
            id: "\(macgitUID):gitlab:\(hostIdentifier):\(profile.id)",
            macgitUID: macgitUID,
            provider: .gitlab,
            hostURL: normalizedHost.baseURL,
            providerUserID: String(profile.id),
            username: profile.username,
            displayName: profile.name,
            avatarURL: profile.avatarURL,
            scopes: configuration.scopes,
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

    private func validate(
        response: HTTPURLResponse,
        data: Data,
        unauthorizedMeansReauthorization: Bool = false
    ) throws {
        if response.statusCode == 401, unauthorizedMeansReauthorization {
            throw GitProviderAuthError.reauthorizationRequired
        }
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw GitProviderAuthError.providerMessage(
                payload?.message ?? payload?.errorDescription ?? "GitLab request failed (HTTP \(response.statusCode))."
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
            return .providerMessage(message ?? "GitLab device authorization failed.")
        }
    }
}

private extension GitLabProviderAuthService {
    struct DeviceAuthorizationResponse: Decodable {
        var deviceCode: String
        var userCode: String
        var verificationURI: String
        var verificationURIComplete: String?
        var expiresIn: Int
        var interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case verificationURIComplete = "verification_uri_complete"
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
        var username: String
        var name: String?
        var avatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case username
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
