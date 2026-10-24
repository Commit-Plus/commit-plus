// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Validates Azure DevOps personal access tokens for one organization.
struct AzureDevOpsProviderAuthService {
    static let rejectedTokenMessage = "The personal access token is invalid, expired, or has no access to this organization."

    private let httpClient: GitProviderHTTPClient
    private let now: () -> Date

    init(
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.now = now
    }

    /// Azure DevOps takes a PAT as the Basic password with an empty user name.
    static func authorizationHeader(for token: GitProviderToken) -> String {
        "Basic " + Data(":\(token.accessToken)".utf8).base64EncodedString()
    }

    /// Prepares an Azure DevOps API request; without the suppress header a rejected
    /// token is redirected to an HTML sign-in page instead of returning 401.
    static func apiRequest(url: URL, token: GitProviderToken) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(authorizationHeader(for: token), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Suppress", forHTTPHeaderField: "X-TFS-FedAuthRedirect")
        return request
    }

    /// 203 is how Azure DevOps answers with a sign-in page when the token is not accepted.
    static func isRejected(_ response: HTTPURLResponse) -> Bool {
        response.statusCode == 401 || response.statusCode == 203
            || (300..<400).contains(response.statusCode)
            || response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("json") == false
    }

    /// `connectionData` accepts a PAT of any scope, unlike the profile API.
    func fetchAccount(
        organization: String,
        token: GitProviderToken,
        macgitUID: String
    ) async throws -> GitProviderAccount {
        let organizationURL = AzureReposRemote.organizationURL(organization)
        let request = Self.apiRequest(url: organizationURL.appending(path: "_apis/connectionData"), token: token)
        let (data, response) = try await httpClient.data(for: request)
        // Distinct messages so a failed connection says which check failed.
        if response.statusCode == 401 {
            throw GitProviderAuthError.providerMessage(Self.rejectedTokenMessage)
        }
        if response.statusCode == 403 || response.statusCode == 404 {
            throw GitProviderAuthError.providerMessage(
                "This token has no access to the \(organization) organization (HTTP \(response.statusCode))."
            )
        }
        if Self.isRejected(response) {
            let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "no content type"
            throw GitProviderAuthError.providerMessage(
                "Azure DevOps did not accept the token and returned a sign-in page (HTTP \(response.statusCode), \(contentType))."
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitProviderAuthError.providerMessage("Azure DevOps request failed (HTTP \(response.statusCode)).")
        }
        let payload: ConnectionData
        do {
            payload = try JSONDecoder().decode(ConnectionData.self, from: data)
        } catch {
            throw GitProviderAuthError.providerMessage(
                "Azure DevOps returned an unexpected account response (HTTP \(response.statusCode), \(data.count) bytes)."
            )
        }

        let user = payload.authenticatedUser
        let displayName = user.providerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountName = user.properties?.account?.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.id.isEmpty,
              let username = [accountName, displayName].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw GitProviderAuthError.invalidResponse
        }
        let timestamp = now()
        let hostIdentifier = GitProviderHost.accountHostIdentifier(organizationURL)
        return GitProviderAccount(
            id: "\(macgitUID):\(GitProviderKind.azureDevOps.rawValue):\(hostIdentifier):\(user.id)",
            macgitUID: macgitUID,
            provider: .azureDevOps,
            hostURL: organizationURL,
            providerUserID: user.id,
            username: username,
            displayName: displayName?.isEmpty == false ? displayName : nil,
            avatarURL: nil,
            scopes: [],
            permissions: ["authentication": "personalAccessToken"],
            tokenStatus: .valid,
            connectedAt: timestamp,
            lastValidatedAt: timestamp
        )
    }

    private struct ConnectionData: Decodable {
        var authenticatedUser: User
    }

    private struct User: Decodable {
        var id: String
        var providerDisplayName: String?
        var properties: Properties?
    }

    private struct Properties: Decodable {
        var account: Value?

        enum CodingKeys: String, CodingKey {
            case account = "Account"
        }
    }

    private struct Value: Decodable {
        var value: String

        enum CodingKeys: String, CodingKey {
            case value = "$value"
        }
    }
}
