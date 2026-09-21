// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct BranchProtectionService {
    enum Status: Equatable {
        case protected
        case unprotected
        case unavailable
        case unsupported
    }

    var httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()

    func status(
        branch: String,
        identity: GitRemoteIdentity,
        token: GitProviderToken?
    ) async -> Status {
        let encode: (String) -> String = {
            $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0
        }
        let endpoint: String
        switch identity.provider {
        case .github:
            endpoint = "https://api.github.com/repos/\(encode(identity.ownerPath))/\(encode(identity.repositoryName))/branches/\(encode(branch))"
        case .gitlab:
            endpoint = "\(identity.hostURL.absoluteString)/api/v4/projects/\(encode(identity.ownerPath + "/" + identity.repositoryName))/repository/branches/\(encode(branch))"
        case .bitbucket:
            return .unsupported
        }
        guard let url = URL(string: endpoint) else { return .unavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.accessToken.isEmpty {
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await httpClient.data(for: request)
            guard response.statusCode == 200 else { return .unavailable }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return payload.protected ? .protected : .unprotected
        } catch {
            return .unavailable
        }
    }

    private struct Payload: Decodable {
        let protected: Bool
    }
}
