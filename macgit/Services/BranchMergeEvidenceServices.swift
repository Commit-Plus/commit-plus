// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct GitHubBranchMergeEvidenceService: BranchMergeEvidenceProviding {
    var httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()

    func mergedChanges(
        targetRepository: GitRepositoryIdentity,
        sourceRepository: GitRepositoryIdentity,
        sourceBranch: String,
        token: GitProviderToken
    ) async throws -> [ProviderMergedChange] {
        guard targetRepository.provider == .github, sourceRepository.provider == .github else {
            throw PullRequestProviderError.unsupportedProvider
        }
        let host = GitProviderHost(kind: .github, baseURL: targetRepository.hostURL)
        guard GitProviderHost.identityKey(host.baseURL) == GitProviderHost.identityKey(sourceRepository.hostURL) else {
            return []
        }
        var components = URLComponents(
            url: host.apiURL.appending(path: "repos/\(targetRepository.owner)/\(targetRepository.name)/pulls"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "state", value: "closed"),
            URLQueryItem(name: "head", value: "\(sourceRepository.owner):\(sourceBranch)"),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encodedQuery
        guard let url = components?.url else { throw PullRequestProviderError.repositoryUnavailable }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await httpClient.data(for: request)
        try validate(response, data: data, provider: "GitHub")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let values = try decoder.decode([GitHubMergedPullRequest].self, from: data)
        return values.compactMap { value in
            guard value.mergedAt != nil,
                  value.head.repository.fullName.caseInsensitiveCompare("\(sourceRepository.owner)/\(sourceRepository.name)") == .orderedSame,
                  value.head.reference == sourceBranch else { return nil }
            return ProviderMergedChange(
                number: value.number,
                title: value.title,
                sourceRepository: sourceRepository,
                sourceBranch: value.head.reference,
                sourceSHA: value.head.sha,
                targetRepository: targetRepository,
                targetBranch: value.base.reference,
                webURL: value.webURL,
                mergedAt: value.mergedAt
            )
        }
    }

    private struct GitHubMergedPullRequest: Decodable {
        struct Repository: Decodable { let fullName: String; enum CodingKeys: String, CodingKey { case fullName = "full_name" } }
        struct Reference: Decodable {
            let reference: String
            let sha: String
            let repository: Repository
            enum CodingKeys: String, CodingKey { case reference = "ref"; case sha; case repository = "repo" }
        }
        struct BaseReference: Decodable { let reference: String; enum CodingKeys: String, CodingKey { case reference = "ref" } }
        let number: Int
        let title: String
        let head: Reference
        let base: BaseReference
        let webURL: URL
        let mergedAt: Date?
        enum CodingKeys: String, CodingKey { case number, title, head, base; case webURL = "html_url"; case mergedAt = "merged_at" }
    }
}

struct GitLabBranchMergeEvidenceService: BranchMergeEvidenceProviding {
    var httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()

    func mergedChanges(
        targetRepository: GitRepositoryIdentity,
        sourceRepository: GitRepositoryIdentity,
        sourceBranch: String,
        token: GitProviderToken
    ) async throws -> [ProviderMergedChange] {
        guard targetRepository.provider == .gitlab, sourceRepository.provider == .gitlab else {
            throw PullRequestProviderError.unsupportedProvider
        }
        guard GitProviderHost.identityKey(targetRepository.hostURL) == GitProviderHost.identityKey(sourceRepository.hostURL) else { return [] }
        let project = "\(targetRepository.owner)/\(targetRepository.name)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = project.addingPercentEncoding(withAllowedCharacters: allowed),
              var components = URLComponents(url: targetRepository.hostURL, resolvingAgainstBaseURL: false) else {
            throw PullRequestProviderError.repositoryUnavailable
        }
        let root = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = (root.isEmpty ? "" : "/\(root)") + "/api/v4/projects/\(encoded)/merge_requests"
        components.queryItems = [
            URLQueryItem(name: "state", value: "merged"),
            URLQueryItem(name: "source_branch", value: sourceBranch),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw PullRequestProviderError.repositoryUnavailable }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await httpClient.data(for: request)
        try validate(response, data: data, provider: "GitLab")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateFormatter().date(from: value) { return date }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid GitLab date")
        }
        let values = try decoder.decode([GitLabMergedRequest].self, from: data)
        let sourcePath = "\(sourceRepository.owner)/\(sourceRepository.name)"
        var result: [ProviderMergedChange] = []
        var sourcePathsByID: [Int: String] = [:]
        for value in values where value.state == "merged" && value.sourceBranch == sourceBranch {
            let matchesSourceRepository: Bool
            if value.sourceProjectID == value.targetProjectID {
                matchesSourceRepository = sourcePath.caseInsensitiveCompare(project) == .orderedSame
            } else if let sourceProjectID = value.sourceProjectID {
                let resolvedPath: String?
                if let cached = sourcePathsByID[sourceProjectID] {
                    resolvedPath = cached
                } else {
                    do {
                        resolvedPath = try await projectPath(
                            id: sourceProjectID,
                            hostURL: targetRepository.hostURL,
                            token: token
                        )
                    } catch PullRequestProviderError.reauthorizationRequired {
                        throw PullRequestProviderError.reauthorizationRequired
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        resolvedPath = nil
                    }
                    if let resolvedPath { sourcePathsByID[sourceProjectID] = resolvedPath }
                }
                matchesSourceRepository = resolvedPath?.caseInsensitiveCompare(sourcePath) == .orderedSame
            } else {
                matchesSourceRepository = false
            }
            guard matchesSourceRepository else { continue }
            result.append(ProviderMergedChange(
                number: value.iid,
                title: value.title,
                sourceRepository: sourceRepository,
                sourceBranch: value.sourceBranch,
                sourceSHA: value.sha,
                targetRepository: targetRepository,
                targetBranch: value.targetBranch,
                webURL: value.webURL,
                mergedAt: value.mergedAt
            ))
        }
        return result
    }

    private func projectPath(id: Int, hostURL: URL, token: GitProviderToken) async throws -> String? {
        guard var components = URLComponents(url: hostURL, resolvingAgainstBaseURL: false) else { return nil }
        let root = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = (root.isEmpty ? "" : "/\(root)") + "/api/v4/projects/\(id)"
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await httpClient.data(for: request)
        try validate(response, data: data, provider: "GitLab")
        return try JSONDecoder().decode(GitLabProjectIdentity.self, from: data).pathWithNamespace
    }

    private struct GitLabMergedRequest: Decodable {
        struct References: Decodable { let full: String? }
        let iid: Int
        let title: String
        let state: String
        let sourceBranch: String
        let targetBranch: String
        let sha: String
        let sourceProjectID: Int?
        let targetProjectID: Int?
        let webURL: URL
        let mergedAt: Date?
        let references: References?
        enum CodingKeys: String, CodingKey {
            case iid, title, state, sha, references
            case sourceBranch = "source_branch"; case targetBranch = "target_branch"
            case sourceProjectID = "source_project_id"; case targetProjectID = "target_project_id"
            case webURL = "web_url"; case mergedAt = "merged_at"
        }
    }

    private struct GitLabProjectIdentity: Decodable {
        let pathWithNamespace: String
        enum CodingKeys: String, CodingKey { case pathWithNamespace = "path_with_namespace" }
    }
}

private func validate(_ response: HTTPURLResponse, data: Data, provider: String) throws {
    switch response.statusCode {
    case 200..<300: return
    case 401: throw PullRequestProviderError.reauthorizationRequired
    case 403, 429: throw PullRequestProviderError.permissionDenied
    case 404: throw PullRequestProviderError.repositoryUnavailable
    default:
        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw PullRequestProviderError.providerMessage(message?.isEmpty == false ? message! : "\(provider) merge detection failed (HTTP \(response.statusCode)).")
    }
}

