// SPDX-License-Identifier: AGPL-3.0-or-later
import CryptoKit
import Foundation

extension GitStatusService {
    struct RepositoryInfo: Equatable {
        var branch: String?
        var changed: Int?
        var commits: Int?
        var firstCommit: Date?
        var lastCommit: Date?
        var remotes: [RepositoryBookmarkRemote] = []
    }

    func repositoryInfo(in url: URL) async -> RepositoryInfo {
        async let status = repoPickerStatus(in: url)
        async let count = try? runGit(arguments: ["rev-list", "--count", "HEAD"], in: url)
        async let dates = try? runGit(arguments: ["log", "--format=%ct", "HEAD"], in: url)
        async let remoteDetails = try? repositoryBookmarkRemotes(in: url)
        let snapshot = await status
        let timestamps = await dates?.split(separator: "\n").compactMap { Double($0) } ?? []
        let remotes = await remoteDetails ?? []
        return await RepositoryInfo(
            branch: snapshot.currentBranch, changed: snapshot.changedFileCount,
            commits: count.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) },
            firstCommit: timestamps.min().map(Date.init(timeIntervalSince1970:)),
            lastCommit: timestamps.max().map(Date.init(timeIntervalSince1970:)), remotes: remotes
        )
    }

    func repositoryStatistics(in url: URL, query: RepositoryStatisticsQuery, repositoryID: UUID? = nil, cache injectedCache: LocalDataStore? = nil) async throws -> RepositoryStatistics {
        _ = try await runGit(arguments: ["rev-parse", "--git-dir"], in: url)
        let head = try? await runGit(arguments: ["rev-parse", "--verify", "HEAD"], in: url)
        let shallow = (try? await runGit(arguments: ["rev-parse", "--is-shallow-repository"], in: url))?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        let shallowPath = try? await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-path", "shallow"], in: url)
        let shallowDigest = await Task.detached(priority: .utility) {
            guard let shallowPath, let data = try? Data(contentsOf: URL(fileURLWithPath: shallowPath.trimmingCharacters(in: .whitespacesAndNewlines))) else { return "" }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
        let replacements = (try? await runGit(arguments: ["for-each-ref", "--format=%(refname):%(objectname)", "refs/replace"], in: url)) ?? ""
        let fingerprint = (head ?? "unborn") + "|shallow:\(shallow)|\(shallowDigest)|\(replacements)"
        let identity: String
        if let repositoryID { identity = repositoryID.uuidString }
        else {
            identity = await MainActor.run {
                RepositoryCatalogStore.shared.snapshot.repositories.first { $0.path == RepositoryCatalogSnapshot.path(url) }?.id.uuidString ?? RepositoryCatalogSnapshot.path(url)
            }
        }
        let cache = await MainActor.run { injectedCache ?? LocalDataStore.shared }
        let keyEncoder = JSONEncoder()
        keyEncoder.outputFormatting = [.sortedKeys]
        let keyData = try keyEncoder.encode(query)
        let key = SHA256.hash(data: Data(identity.utf8) + keyData).map { String(format: "%02x", $0) }.joined()
        if let cached = try? await cache.readValue(RepositoryStatistics.self, in: "repositoryStatisticsCache", id: key), cached.fingerprint == fingerprint {
            return cached
        }
        var result = RepositoryStatistics()
        if head != nil {
            let log = try await runGit(arguments: ["log", "HEAD", "--format=%at%x09%an%x09%ae", "--no-show-signature"], in: url)
            let worker = Task.detached(priority: .utility) { RepositoryStatisticsAggregator.aggregate(log, query: query) }
            result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        }
        try Task.checkCancellation()
        result.fingerprint = fingerprint
        result.isShallow = shallow
        let saved = result
        // Cache failure must never prevent viewing statistics.
        if ((try? JSONEncoder().encode(saved).count) ?? Int.max) <= 4 * 1024 * 1024 {
            try? await cache.transaction(reading: ["repositoryStatisticsCache"]) { transaction in
            let old = try transaction.values(RepositoryStatistics.self, in: "repositoryStatisticsCache")
            for item in old.sorted(by: { $0.value.calculatedAt > $1.value.calculatedAt }).dropFirst(39) {
                transaction.remove(in: "repositoryStatisticsCache", id: item.key)
            }
            try transaction.set(saved, in: "repositoryStatisticsCache", id: key)
            }
        }
        return result
    }

}
