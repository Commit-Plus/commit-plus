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
