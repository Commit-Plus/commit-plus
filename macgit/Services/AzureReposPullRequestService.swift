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

/// Azure DevOps Git REST API (api-version 7.1). Azure returns no patches, so diffs are
/// built locally from both file versions.
struct AzureReposPullRequestService: PullRequestProviding {
    static let apiVersion = "7.1"
    static let maximumDiffFileCount = 100
    static let maximumDiffFileBytes = 1_000_000
    static let mergePollAttempts = 10

    private let httpClient: GitProviderHTTPClient
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()
    private let unifiedDiff: (Data, Data, String) async throws -> String
    private let mergePollDelay: () async throws -> Void

    init(
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        unifiedDiff: @escaping (Data, Data, String) async throws -> String = { original, modified, path in
            try await GitStatusService.shared.unifiedDiff(original: original, modified: modified, path: path)
        },
        mergePollDelay: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }
    ) {
        self.httpClient = httpClient
        self.unifiedDiff = unifiedDiff
        self.mergePollDelay = mergePollDelay
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeAzureDate)
        self.decoder = decoder
    }

    func listPullRequests(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        filter: PullRequestListFilter,
        page: Int,
        perPage: Int
    ) async throws -> PullRequestListPage {
        let normalizedPage = max(1, page)
        let normalizedPerPage = min(max(1, perPage), 100)
        // Closed has no single Azure status (completed and abandoned); the controller filters `all`.
        let url = try repositoryURL(repository, path: ["pullrequests"], query: [
            URLQueryItem(name: "searchCriteria.status", value: filter == .open ? "active" : "all"),
            URLQueryItem(name: "$top", value: String(normalizedPerPage + 1)),
            URLQueryItem(name: "$skip", value: String((normalizedPage - 1) * normalizedPerPage)),
        ])
        let list: AzureList<AzurePullRequest> = try await get(url, token: token)
        let summaries = list.value.map { $0.summary(repository: repository) }
        return PullRequestListPage(
            items: Array(summaries.prefix(normalizedPerPage)),
            page: normalizedPage,
            perPage: normalizedPerPage,
            hasPreviousPage: normalizedPage > 1,
            hasNextPage: summaries.count > normalizedPerPage
        )
    }

    func openPullRequest(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        sourceBranch: String
    ) async throws -> PullRequestSummary? {
        let url = try repositoryURL(repository, path: ["pullrequests"], query: [
            URLQueryItem(name: "searchCriteria.sourceRefName", value: "refs/heads/\(sourceBranch)"),
            URLQueryItem(name: "searchCriteria.status", value: "all"),
            URLQueryItem(name: "$top", value: "50"),
        ])
        let list: AzureList<AzurePullRequest> = try await get(url, token: token)
        return list.value.map { $0.summary(repository: repository) }.preferringOpenPullRequest
    }

    func pullRequestDetail(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> PullRequestDetail {
        let pullRequest: AzurePullRequest = try await get(
            try repositoryURL(repository, path: ["pullrequests", String(number)]),
            token: token
        )
        let threads: AzureList<AzureThread> = try await get(
            try repositoryURL(repository, path: ["pullrequests", String(number), "threads"]),
            token: token
        )
        let summary = pullRequest.summary(repository: repository)
        let comments = threads.value
            .filter { $0.isDeleted != true }
            .flatMap { $0.comments(pullRequestWebURL: summary.webURL) }
            .sorted { $0.createdAt < $1.createdAt }
        return PullRequestDetail(
            summary: summary,
            body: pullRequest.description ?? "",
            reviewers: (pullRequest.reviewers ?? []).map(\.author),
            assignees: [],
            comments: comments,
            changesURL: summary.webURL.appending(queryItems: [URLQueryItem(name: "_a", value: "files")])
        )
    }

    func pullRequestChanges(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> [PullRequestChangedFile] {
        let iterations: AzureList<AzureIteration> = try await get(
            try repositoryURL(repository, path: ["pullrequests", String(number), "iterations"]),
            token: token
        )
        guard let iteration = iterations.value.max(by: { $0.id < $1.id }) else { return [] }

        var entries: [AzureChangeEntry] = []
        var skip = 0
        while true {
            let url = try repositoryURL(
                repository,
                path: ["pullrequests", String(number), "iterations", String(iteration.id), "changes"],
                query: [
                    URLQueryItem(name: "$compareTo", value: "0"),
                    URLQueryItem(name: "$top", value: "2000"),
                    URLQueryItem(name: "$skip", value: String(skip)),
                ]
            )
            let page: AzureChanges = try await get(url, token: token)
            entries.append(contentsOf: page.changeEntries.filter { $0.item.isFolder != true })
            guard let nextSkip = page.nextSkip, nextSkip > skip else { break }
            skip = nextSkip
        }

        let base = iteration.commonRefCommit?.commitId
        let head = iteration.sourceRefCommit?.commitId
        var files = [PullRequestChangedFile?](repeating: nil, count: entries.count)
        // Four files at a time keeps large pull requests from flooding Azure DevOps.
        try await withThrowingTaskGroup(of: (Int, PullRequestChangedFile).self) { group in
            var next = 0
            func addNext() {
                guard next < entries.count else { return }
                let index = next
                next += 1
                group.addTask { @MainActor in
                    (index, try await changedFile(
                        entries[index], index: index, base: base, head: head,
                        repository: repository, token: token
                    ))
                }
            }
            for _ in 0..<4 { addNext() }
            while let (index, file) = try await group.next() {
                files[index] = file
                addNext()
            }
        }
        return files.compactMap(\.self)
    }

    func createPullRequest(
        _ draft: PullRequestDraft,
        token: GitProviderToken
    ) async throws -> PullRequestCreationResult {
        let body = AzureCreatePullRequest(
            sourceRefName: "refs/heads/\(draft.sourceBranch)",
            targetRefName: "refs/heads/\(draft.targetBranch)",
            title: draft.title,
            description: draft.body
        )
        let pullRequest: AzurePullRequest = try await send(
            "POST",
            try repositoryURL(draft.repository, path: ["pullrequests"]),
            body: body,
            token: token
        )
        return PullRequestCreationResult(summary: pullRequest.summary(repository: draft.repository))
    }

    func createComment(
        body: String,
        on pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        let thread = AzureCreateThread(comments: [.init(parentCommentId: 0, content: body, commentType: 1)], status: 1)
        let _: AzureThread = try await send(
            "POST",
            try repositoryURL(repository, path: ["pullrequests", String(pullRequest.number), "threads"]),
            body: thread,
            token: token
        )
    }

    func mergePullRequest(
        _ pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        let url = try repositoryURL(repository, path: ["pullrequests", String(pullRequest.number)])
        var commitID = pullRequest.source.sha
        if commitID == nil {
            let current: AzurePullRequest = try await get(url, token: token)
            commitID = current.lastMergeSourceCommit?.commitId
        }
        guard let commitID else {
            throw PullRequestProviderError.providerMessage("Azure DevOps did not report the pull request's latest commit.")
        }
        var result: AzurePullRequest = try await send(
            "PATCH",
            url,
            body: AzureCompletePullRequest(lastMergeSourceCommit: .init(commitId: commitID)),
            token: token
        )
        // Completion is queued; poll until Azure finishes or reports why it could not.
        for attempt in 0...Self.mergePollAttempts {
            if result.status == "completed" { return }
            if ["conflicts", "rejectedByPolicy", "failure"].contains(result.mergeStatus ?? "") {
                throw PullRequestProviderError.providerMessage(
                    result.mergeFailureMessage?.nilIfBlank
                        ?? (result.mergeStatus == "conflicts"
                            ? "The pull request has merge conflicts."
                            : "Azure DevOps could not complete the pull request.")
                )
            }
            guard attempt < Self.mergePollAttempts else { break }
            try await mergePollDelay()
            result = try await get(url, token: token)
        }
        throw PullRequestProviderError.providerMessage(
            "Azure DevOps is still completing the pull request. Refresh to see the result."
        )
    }

    // MARK: - Changes

    private func changedFile(
        _ entry: AzureChangeEntry,
        index: Int,
        base: String?,
        head: String?,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> PullRequestChangedFile {
        let path = entry.item.path
        let originalPath = entry.originalPath ?? entry.sourceServerItem ?? path
        let status = entry.status
        func file(patch: String?, reason: String?) -> PullRequestChangedFile {
            let hunks = patch.map { Self.lineCounts(in: $0) }
            return PullRequestChangedFile(
                path: Self.displayPath(path),
                previousPath: status == .renamed ? Self.displayPath(originalPath) : nil,
                status: status,
                additions: hunks?.additions,
                deletions: hunks?.deletions,
                patch: patch,
                patchUnavailableReason: reason
            )
        }
        guard index < Self.maximumDiffFileCount else {
            return file(patch: nil, reason: "This pull request has more than \(Self.maximumDiffFileCount) files. View the diff on Azure DevOps.")
        }
        guard let base, let head else {
            return file(patch: nil, reason: "The diff is unavailable. View it on Azure DevOps.")
        }
        let original = status == .added ? Data() : try await content(path: originalPath, commit: base, repository: repository, token: token)
        let modified = status == .deleted ? Data() : try await content(path: path, commit: head, repository: repository, token: token)
        if original.count > Self.maximumDiffFileBytes || modified.count > Self.maximumDiffFileBytes {
            return file(patch: nil, reason: "This file is larger than 1 MB. View the diff on Azure DevOps.")
        }
        if Self.isBinary(original) || Self.isBinary(modified) {
            return file(patch: nil, reason: "Binary file. View the diff on Azure DevOps.")
        }
        let patch = try await unifiedDiff(original, modified, Self.displayPath(path))
        return file(patch: patch.isEmpty ? nil : patch, reason: patch.isEmpty ? "No text changes." : nil)
    }

    private func content(
        path: String,
        commit: String,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> Data {
        let url = try repositoryURL(repository, path: ["items"], query: [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "versionDescriptor.versionType", value: "commit"),
            URLQueryItem(name: "versionDescriptor.version", value: commit),
            URLQueryItem(name: "$format", value: "octetStream"),
        ])
        var request = AzureDevOpsProviderAuthService.apiRequest(url: url, token: token)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (data, response) = try await httpClient.data(for: request)
        // File content is not JSON, so only a status or an HTML sign-in page means rejection.
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if response.statusCode == 401 || response.statusCode == 203 || contentType.contains("text/html") {
            throw PullRequestProviderError.reauthorizationRequired
        }
        try validate(response: response, data: data, isWrite: false, checksRejection: false)
        return data
    }

    static func isBinary(_ data: Data) -> Bool {
        data.prefix(8_000).contains(0)
    }

    static func lineCounts(in patch: String) -> (additions: Int, deletions: Int) {
        var additions = 0
        var deletions = 0
        var inHunk = false
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") { inHunk = true; continue }
            guard inHunk else { continue }
            if line.hasPrefix("+") { additions += 1 } else if line.hasPrefix("-") { deletions += 1 }
        }
        return (additions, deletions)
    }

    private static func displayPath(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    // MARK: - Requests

    func repositoryURL(
        _ repository: GitRepositoryIdentity,
        path: [String],
        query: [URLQueryItem] = []
    ) throws -> URL {
        guard repository.provider == .azureDevOps else {
            throw PullRequestProviderError.unsupportedProvider
        }
        var url = repository.hostURL
            .appending(path: repository.owner)
            .appending(path: "_apis/git/repositories")
            .appending(path: repository.name)
        for component in path { url = url.appending(path: component) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw PullRequestProviderError.repositoryUnavailable
        }
        components.queryItems = query + [URLQueryItem(name: "api-version", value: Self.apiVersion)]
        // URLComponents leaves `+` unescaped, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let result = components.url else { throw PullRequestProviderError.repositoryUnavailable }
        return result
    }

    private func get<Response: Decodable>(_ url: URL, token: GitProviderToken) async throws -> Response {
        let request = AzureDevOpsProviderAuthService.apiRequest(url: url, token: token)
        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data, isWrite: false)
        return try decode(data)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String,
        _ url: URL,
        body: Body,
        token: GitProviderToken
    ) async throws -> Response {
        var request = AzureDevOpsProviderAuthService.apiRequest(url: url, token: token)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data, isWrite: true)
        return try decode(data)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PullRequestProviderError.providerMessage("Azure DevOps returned an invalid pull request response.")
        }
    }

    func validate(response: HTTPURLResponse, data: Data, isWrite: Bool, checksRejection: Bool = true) throws {
        if checksRejection, AzureDevOpsProviderAuthService.isRejected(response) {
            throw PullRequestProviderError.reauthorizationRequired
        }
        guard !(200..<300).contains(response.statusCode) else { return }
        switch response.statusCode {
        case 401:
            throw PullRequestProviderError.reauthorizationRequired
        case 403:
            if isWrite {
                throw PullRequestProviderError.providerMessage("The personal access token needs the Code (Read & Write) scope.")
            }
            throw PullRequestProviderError.permissionDenied
        case 404:
            throw PullRequestProviderError.repositoryUnavailable
        default:
            let message = (try? JSONDecoder().decode(AzureErrorResponse.self, from: data))?.message.nilIfBlank
            throw PullRequestProviderError.providerMessage(
                message ?? "Azure DevOps request failed (HTTP \(response.statusCode))."
            )
        }
    }

    /// Azure writes up to seven fractional digits, which `ISO8601DateFormatter` rejects.
    private static func decodeAzureDate(from decoder: Decoder) throws -> Date {
        let value = try decoder.singleValueContainer().decode(String.self)
        if let date = parseDate(value) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(value)"))
    }

    static func parseDate(_ value: String) -> Date? {
        var trimmed = value
        if let dot = value.firstIndex(of: ".") {
            let suffixStart = value[dot...].firstIndex { $0 == "Z" || $0 == "+" || $0 == "-" } ?? value.endIndex
            trimmed = String(value[..<dot]) + String(value[suffixStart...])
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: trimmed)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Azure payloads

private struct AzureList<Element: Decodable>: Decodable {
    var value: [Element]
}

private struct AzureErrorResponse: Decodable {
    var message: String
}

private struct AzureIdentity: Decodable {
    var displayName: String?
    var uniqueName: String?

    var author: PullRequestAuthor {
        PullRequestAuthor(username: uniqueName?.nilIfBlank ?? displayName ?? "", avatarURL: nil)
    }
}

private struct AzureCommitRef: Codable {
    var commitId: String
}

private struct AzurePullRequest: Decodable {
    var pullRequestId: Int
    var title: String?
    var description: String?
    var status: String
    var isDraft: Bool?
    var createdBy: AzureIdentity?
    var creationDate: Date
    var closedDate: Date?
    var sourceRefName: String
    var targetRefName: String
    var mergeStatus: String?
    var mergeFailureMessage: String?
    var lastMergeSourceCommit: AzureCommitRef?
    var lastMergeTargetCommit: AzureCommitRef?
    var reviewers: [AzureIdentity]?

    func summary(repository: GitRepositoryIdentity) -> PullRequestSummary {
        let state: PullRequestState = switch status {
        case "completed": .merged
        case "abandoned": .closed
        default: isDraft == true ? .draft : .open
        }
        let readiness: PullRequestMergeReadiness = switch mergeStatus {
        case "succeeded": .ready
        case "conflicts", "rejectedByPolicy", "failure": .blocked
        default: .unknown
        }
        let source = Self.branchName(sourceRefName)
        let target = Self.branchName(targetRefName)
        let webURL = (repository.browserURL ?? repository.hostURL)
            .appending(path: "pullrequest")
            .appending(path: String(pullRequestId))
        return PullRequestSummary(
            number: pullRequestId,
            title: title ?? "",
            state: state,
            author: createdBy?.author ?? PullRequestAuthor(username: "", avatarURL: nil),
            source: PullRequestBranchRef(label: source, ref: source, sha: lastMergeSourceCommit?.commitId),
            target: PullRequestBranchRef(label: target, ref: target, sha: lastMergeTargetCommit?.commitId),
            webURL: webURL,
            createdAt: creationDate,
            updatedAt: closedDate ?? creationDate,
            mergedAt: state == .merged ? closedDate : nil,
            mergeReadiness: readiness
        )
    }

    static func branchName(_ refName: String) -> String {
        refName.hasPrefix("refs/heads/") ? String(refName.dropFirst("refs/heads/".count)) : refName
    }
}

private struct AzureThread: Decodable {
    struct Position: Decodable {
        var line: Int
    }

    struct Context: Decodable {
        var filePath: String?
        var rightFileStart: Position?
        var leftFileStart: Position?
    }

    struct Comment: Decodable {
        var id: Int
        var author: AzureIdentity?
        var content: String?
        var publishedDate: Date?
        var lastUpdatedDate: Date?
        var commentType: String?
        var isDeleted: Bool?
    }

    var id: Int
    var isDeleted: Bool?
    var threadContext: Context?
    var comments: [Comment]?

    func comments(pullRequestWebURL: URL) -> [PullRequestComment] {
        let reviewContext = threadContext?.filePath.map { path in
            PullRequestReviewContext(
                path: path.hasPrefix("/") ? String(path.dropFirst()) : path,
                diffHunk: nil,
                line: threadContext?.rightFileStart?.line ?? threadContext?.leftFileStart?.line,
                startLine: nil,
                side: threadContext?.rightFileStart == nil && threadContext?.leftFileStart != nil ? "LEFT" : "RIGHT",
                isOutdated: false
            )
        }
        let webURL = pullRequestWebURL.appending(queryItems: [URLQueryItem(name: "discussionId", value: String(id))])
        return (comments ?? []).compactMap { comment in
            guard comment.commentType == "text", comment.isDeleted != true,
                  let content = comment.content, let published = comment.publishedDate else { return nil }
            return PullRequestComment(
                id: id * 1000 + comment.id,
                author: comment.author?.author ?? PullRequestAuthor(username: "", avatarURL: nil),
                body: content,
                webURL: webURL,
                createdAt: published,
                updatedAt: comment.lastUpdatedDate ?? published,
                reviewContext: reviewContext
            )
        }
    }
}

private struct AzureIteration: Decodable {
    var id: Int
    var sourceRefCommit: AzureCommitRef?
    var commonRefCommit: AzureCommitRef?
}

private struct AzureChanges: Decodable {
    var changeEntries: [AzureChangeEntry]
    var nextSkip: Int?
}

private struct AzureChangeEntry: Decodable {
    struct Item: Decodable {
        var path: String
        var isFolder: Bool?
    }

    var changeType: String
    var item: Item
    var originalPath: String?
    var sourceServerItem: String?

    /// `changeType` is a comma-separated flag list such as "edit, rename".
    var status: CommitFileStatus {
        let flags = Set(changeType.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        if flags.contains("add") { return .added }
        if flags.contains("delete") { return .deleted }
        if flags.contains("rename") { return .renamed }
        return .modified
    }
}

private struct AzureCreatePullRequest: Encodable {
    var sourceRefName: String
    var targetRefName: String
    var title: String
    var description: String
}

private struct AzureCreateThread: Encodable {
    struct Comment: Encodable {
        var parentCommentId: Int
        var content: String
        var commentType: Int
    }

    var comments: [Comment]
    var status: Int
}

private struct AzureCompletePullRequest: Encodable {
    struct CompletionOptions: Encodable {
        var mergeStrategy = "noFastForward"
        var deleteSourceBranch = false
    }

    var status = "completed"
    var lastMergeSourceCommit: AzureCommitRef
    var completionOptions = CompletionOptions()
}
