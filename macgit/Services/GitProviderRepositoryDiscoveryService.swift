// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct GitProviderRepositoryDiscoveryService {
    var httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()

    @MainActor
    func repositories(account: GitProviderAccount, resolver: GitProviderCredentialResolver, page: Int) async throws -> GitProviderRepositoryPage {
        let token: GitProviderToken?
        if let tokenProvider = resolver.tokenProvider {
            token = try await tokenProvider(account)
        } else {
            token = try resolver.tokenVault.readToken(for: account)
        }
        guard let token else { throw GitProviderCredentialError.tokenUnavailable(username: account.username) }
        return try await repositories(account: account, token: token, page: page)
    }

    func repositories(account: GitProviderAccount, token: GitProviderToken, page: Int) async throws -> GitProviderRepositoryPage {
        guard account.provider != .bitbucket else { throw GitProviderCredentialError.unsupportedRemote }
        if account.provider == .azureDevOps {
            return try await azureRepositories(account: account, token: token, page: page)
        }
        let host = GitProviderHost(kind: account.provider, baseURL: account.hostURL)
        let endpoint = host.apiURL.appending(path: account.provider == .github ? "user/repos" : "projects")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "50"), URLQueryItem(name: "page", value: String(max(1, page)))]
        if account.provider == .gitlab { components.queryItems?.append(URLQueryItem(name: "membership", value: "true")) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GitProviderAuthError.providerMessage(response.statusCode == 401
                ? "The personal access token is invalid or expired. Reconnect the account."
                : "Repository discovery failed (HTTP \(response.statusCode)). Check token permissions and repository access.")
        }
        let repositories: [GitProviderDiscoveredRepository]
        do {
            if account.provider == .github {
                repositories = try JSONDecoder().decode([GitHubRepository].self, from: data).map {
                    GitProviderDiscoveredRepository(name: $0.full_name, cloneURL: account.transportProtocol == .ssh ? $0.ssh_url : $0.clone_url)
                }
            } else {
                repositories = try JSONDecoder().decode([GitLabRepository].self, from: data).map {
                    GitProviderDiscoveredRepository(name: $0.path_with_namespace, cloneURL: account.transportProtocol == .ssh ? $0.ssh_url_to_repo : $0.http_url_to_repo)
                }
            }
        } catch { throw GitProviderAuthError.invalidResponse }
        let next = response.value(forHTTPHeaderField: "X-Next-Page")
        let hasNext = account.provider == .gitlab && next != nil ? !(next?.isEmpty ?? true)
            : response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") ?? false
        return GitProviderRepositoryPage(repositories: repositories, hasNextPage: hasNext)
    }

    /// Lists every repository across the organization's projects; Azure returns them in one response.
    private func azureRepositories(account: GitProviderAccount, token: GitProviderToken, page: Int) async throws -> GitProviderRepositoryPage {
        guard page <= 1 else { return GitProviderRepositoryPage(repositories: [], hasNextPage: false) }
        var components = URLComponents(url: account.hostURL.appending(path: "_apis/git/repositories"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api-version", value: "7.1")]
        let request = AzureDevOpsProviderAuthService.apiRequest(url: components.url!, token: token)
        let (data, response) = try await httpClient.data(for: request)
        if AzureDevOpsProviderAuthService.isRejected(response) {
            throw GitProviderAuthError.providerMessage("The personal access token is invalid or expired. Reconnect the account.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitProviderAuthError.providerMessage("Repository discovery failed (HTTP \(response.statusCode)). Check token permissions and repository access.")
        }
        guard let payload = try? JSONDecoder().decode(AzureRepositoryList.self, from: data) else {
            throw GitProviderAuthError.invalidResponse
        }
        let repositories = payload.value
            .filter { $0.isDisabled != true }
            .compactMap { repository -> GitProviderDiscoveredRepository? in
                let cloneURL = account.transportProtocol == .ssh ? repository.sshUrl : repository.remoteUrl.map(Self.removingUserInfo)
                guard let cloneURL else { return nil }
                return GitProviderDiscoveredRepository(name: "\(repository.project.name)/\(repository.name)", cloneURL: cloneURL)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return GitProviderRepositoryPage(repositories: repositories, hasNextPage: false)
    }

    /// Azure embeds the organization as the user (`https://org@dev.azure.com/...`); the account supplies credentials.
    private static func removingUserInfo(_ value: String) -> String {
        guard var components = URLComponents(string: value) else { return value }
        components.user = nil
        components.password = nil
        return components.string ?? value
    }

    private struct AzureRepositoryList: Decodable {
        var value: [AzureRepository]
    }
    private struct AzureRepository: Decodable {
        var name: String
        var project: AzureProject
        var remoteUrl: String?
        var sshUrl: String?
        var isDisabled: Bool?
    }
    private struct AzureProject: Decodable {
        var name: String
    }

    private struct GitHubRepository: Decodable {
        var full_name: String
        var clone_url: String
        var ssh_url: String
    }
    private struct GitLabRepository: Decodable {
        var path_with_namespace: String
        var http_url_to_repo: String
        var ssh_url_to_repo: String
    }
}
