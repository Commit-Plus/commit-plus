// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct JiraValidatedAccount: Equatable {
    var accountID: String
    var displayName: String
    var email: String
    var apiBase: JiraAPIBase
}

protocol JiraIssueServing {
    func validate(siteURL: URL, credential: JiraCredential) async throws -> JiraValidatedAccount
    func sprintFieldID(baseURL: URL, credential: JiraCredential) async throws -> String?
    func searchIssues(
        baseURL: URL,
        credential: JiraCredential,
        jql: String,
        sprintFieldID: String?,
        pageToken: String?
    ) async throws -> JiraIssuePage
}

/// Jira Cloud REST v3 over Basic auth. Error values never carry request headers or response bodies.
struct JiraCloudClient: JiraIssueServing {
    static let pageSize = 50
    static let gatewayURL = URL(string: "https://api.atlassian.com/ex/jira")!
    private static let issueFields = ["summary", "status", "issuetype", "priority", "project", "updated"]

    private let httpClient: GitProviderHTTPClient

    init(httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()) {
        self.httpClient = httpClient
    }

    /// Classic tokens work against the site; scoped tokens are rejected there and must use the gateway.
    func validate(siteURL: URL, credential: JiraCredential) async throws -> JiraValidatedAccount {
        do {
            let myself = try await fetchMyself(baseURL: siteURL, credential: credential)
            return account(from: myself, credential: credential, apiBase: .site)
        } catch JiraError.needsReconnect {
            guard let cloudID = try? await fetchCloudID(siteURL: siteURL) else {
                throw JiraError.invalidCredentials
            }
            do {
                let gatewayBase = Self.gatewayURL.appending(path: cloudID)
                let myself = try await fetchMyself(baseURL: gatewayBase, credential: credential)
                return account(from: myself, credential: credential, apiBase: .gateway(cloudID: cloudID))
            } catch JiraError.needsReconnect, JiraError.forbidden {
                throw JiraError.invalidCredentials
            }
        } catch JiraError.forbidden {
            throw JiraError.invalidCredentials
        }
    }

    func sprintFieldID(baseURL: URL, credential: JiraCredential) async throws -> String? {
        let request = makeRequest(url: baseURL.appending(path: "rest/api/3/field"), credential: credential)
        let data = try await send(request)
        guard let fields = try? JSONDecoder().decode([FieldResponse].self, from: data) else {
            throw JiraError.invalidResponse
        }
        return fields.first { $0.schema?.custom == "com.pyxis.greenhopper.jira:gh-sprint" }?.id
    }

    func searchIssues(
        baseURL: URL,
        credential: JiraCredential,
        jql: String,
        sprintFieldID: String?,
        pageToken: String?
    ) async throws -> JiraIssuePage {
        var request = makeRequest(url: baseURL.appending(path: "rest/api/3/search/jql"), credential: credential)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "jql": jql,
            "maxResults": Self.pageSize,
            "fields": Self.issueFields + (sprintFieldID.map { [$0] } ?? []),
        ]
        if let pageToken { body["nextPageToken"] = pageToken }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawIssues = payload["issues"] as? [[String: Any]] else {
            throw JiraError.invalidResponse
        }
        let issues = rawIssues.compactMap { Self.issue(from: $0, sprintFieldID: sprintFieldID) }
        let isLast = payload["isLast"] as? Bool ?? true
        let nextPageToken = isLast ? nil : payload["nextPageToken"] as? String
        return JiraIssuePage(issues: issues, nextPageToken: nextPageToken)
    }

    // MARK: - Requests

    private func fetchMyself(baseURL: URL, credential: JiraCredential) async throws -> MyselfResponse {
        let request = makeRequest(url: baseURL.appending(path: "rest/api/3/myself"), credential: credential)
        let data = try await send(request)
        guard let myself = try? JSONDecoder().decode(MyselfResponse.self, from: data),
              !myself.accountId.isEmpty else {
            throw JiraError.invalidResponse
        }
        return myself
    }

    private func fetchCloudID(siteURL: URL) async throws -> String {
        var request = URLRequest(url: siteURL.appending(path: "_edge/tenant_info"), timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        guard let tenant = try? JSONDecoder().decode(TenantInfoResponse.self, from: data),
              !tenant.cloudId.isEmpty,
              tenant.cloudId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw JiraError.invalidResponse
        }
        return tenant.cloudId
    }

    private func makeRequest(url: URL, credential: JiraCredential) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch is URLError {
            throw JiraError.unreachable
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw JiraError.unreachable
        }
        try Self.validate(response)
        return data
    }

    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 400:
            throw JiraError.invalidQuery
        case 401:
            throw JiraError.needsReconnect
        case 403:
            throw JiraError.forbidden
        case 429:
            let retryAfter = (response.value(forHTTPHeaderField: "Retry-After")).flatMap { Int($0) }
            throw JiraError.rateLimited(retryAfter: retryAfter)
        case 500...:
            throw JiraError.unreachable
        default:
            throw JiraError.invalidResponse
        }
    }

    private func account(
        from myself: MyselfResponse,
        credential: JiraCredential,
        apiBase: JiraAPIBase
    ) -> JiraValidatedAccount {
        JiraValidatedAccount(
            accountID: myself.accountId,
            displayName: myself.displayName ?? credential.email,
            email: myself.emailAddress ?? credential.email,
            apiBase: apiBase
        )
    }

    // MARK: - Decoding

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    static func issue(from raw: [String: Any], sprintFieldID: String?) -> JiraIssue? {
        guard let id = raw["id"] as? String,
              let key = raw["key"] as? String,
              let fields = raw["fields"] as? [String: Any] else {
            return nil
        }
        let status = fields["status"] as? [String: Any]
        let category = (status?["statusCategory"] as? [String: Any])?["key"] as? String
        let issueType = fields["issuetype"] as? [String: Any]
        let priority = fields["priority"] as? [String: Any]
        let project = fields["project"] as? [String: Any]
        let rawSprints = sprintFieldID.flatMap { fields[$0] as? [[String: Any]] } ?? []
        let sprints = rawSprints.compactMap { sprint -> JiraSprintRef? in
            guard let id = (sprint["id"] as? NSNumber)?.intValue,
                  let name = sprint["name"] as? String else { return nil }
            return JiraSprintRef(id: id, name: name, state: sprint["state"] as? String ?? "")
        }

        return JiraIssue(
            id: id,
            key: key,
            summary: fields["summary"] as? String ?? "",
            statusName: status?["name"] as? String ?? "",
            statusCategory: category.flatMap(JiraStatusCategory.init(rawValue:)),
            issueTypeName: issueType?["name"] as? String ?? "",
            priorityName: priority?["name"] as? String,
            projectKey: project?["key"] as? String ?? "",
            projectName: project?["name"] as? String ?? "",
            updated: (fields["updated"] as? String).flatMap(dateFormatter.date(from:)),
            sprints: sprints
        )
    }

    private struct MyselfResponse: Decodable {
        var accountId: String
        var displayName: String?
        var emailAddress: String?
    }

    private struct TenantInfoResponse: Decodable {
        var cloudId: String
    }

    private struct FieldResponse: Decodable {
        struct Schema: Decodable {
            var custom: String?
        }

        var id: String
        var schema: Schema?
    }
}
