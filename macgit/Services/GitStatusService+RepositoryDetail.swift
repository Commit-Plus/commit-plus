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

    struct RepositorySummaryItem: Identifiable, Equatable {
        var id: String
        var name: String
        var subject: String
        var author: String
        var email: String
        var date: Date?
        var isRemote = false
    }

    struct RepositorySummary: Equatable {
        var branches: [RepositorySummaryItem] = []
        var tags: [RepositorySummaryItem] = []
        var commits: [RepositorySummaryItem] = []
    }

    /// Most recently updated branches and tags plus the latest commits across
    /// all refs, for the repository detail Summary tab.
    func repositorySummary(in url: URL, limit: Int = 5) async -> RepositorySummary {
        async let branchOutput = try? runGit(arguments: [
            "for-each-ref", "--sort=-committerdate",
            "--format=%(refname)%1f%(refname:short)%1f%(symref)%1f%(subject)%1f%(authorname)%1f%(authoremail:trim)%1f%(committerdate:unix)",
            "refs/heads", "refs/remotes",
        ], in: url)
        async let tagOutput = try? runGit(arguments: [
            "for-each-ref", "--sort=-creatordate", "--count=\(limit)",
            "--format=%(refname)%1f%(refname:short)%1f%1f%(contents:subject)%1f%(if)%(taggername)%(then)%(taggername)%1f%(taggeremail:trim)%(else)%(authorname)%1f%(authoremail:trim)%(end)%1f%(creatordate:unix)",
            "refs/tags",
        ], in: url)
        async let commitOutput = try? runGit(arguments: [
            "log", "--all", "-n", "\(limit)", "--no-show-signature", "--format=%H%x1f%h%x1f%x1f%s%x1f%an%x1f%ae%x1f%ct",
        ], in: url)
        // Symbolic refs such as origin/HEAD duplicate the branch they point to.
        let branches = Self.summaryItems(await branchOutput).filter { $0.symref.isEmpty }.prefix(limit).map {
            var item = $0.item
            item.isRemote = item.id.hasPrefix("refs/remotes/")
            return item
        }
        return RepositorySummary(branches: Array(branches),
                                 tags: Self.summaryItems(await tagOutput).map(\.item),
                                 commits: Self.summaryItems(await commitOutput).map(\.item))
    }

    private static func summaryItems(_ output: String?) -> [(item: RepositorySummaryItem, symref: String)] {
        (output ?? "").split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { return nil }
            let item = RepositorySummaryItem(id: fields[0], name: fields[1], subject: fields[3], author: fields[4], email: fields[5],
                                             date: Double(fields[6]).map(Date.init(timeIntervalSince1970:)))
            return (item, fields[2])
        }
    }

    func repositoryInfo(in url: URL) async -> RepositoryInfo {
        async let status = repoPickerStatus(in: url)
        async let count = try? runGit(arguments: ["rev-list", "--all", "--count"], in: url)
        async let dates = try? runGit(arguments: ["log", "--all", "--format=%ct"], in: url)
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

    func repositoryStatistics(in url: URL, query: RepositoryStatisticsQuery, repositoryID: UUID? = nil, cache injectedCache: LocalDataStore? = nil, forceRefresh: Bool = false, now: Date = .now) async throws -> RepositoryStatistics {
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
        if !forceRefresh,
           let cached = try? await cache.readValue(RepositoryStatistics.self, in: "repositoryStatisticsCache", id: key),
           now.timeIntervalSince(cached.calculatedAt) >= 0,
           now.timeIntervalSince(cached.calculatedAt) < 6 * 60 * 60 {
            return cached
        }
        _ = try await runGit(arguments: ["rev-parse", "--git-dir"], in: url)
        let head = try? await runGit(arguments: ["rev-parse", "--verify", "HEAD"], in: url)
        let refs = try await runGit(arguments: ["for-each-ref", "--format=%(objectname)%09%(*objectname)"], in: url)
        // Names and the checked-out branch do not change the aggregate. Include
        // peeled tag targets so switching to an existing tag also reuses it.
        let tips = Set((refs + "\n" + (head ?? "")).split(whereSeparator: { $0.isWhitespace }).map(String.init)).sorted()
        let shallow = (try? await runGit(arguments: ["rev-parse", "--is-shallow-repository"], in: url))?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        let shallowPath = try? await runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-path", "shallow"], in: url)
        let shallowDigest = await Task.detached(priority: .utility) {
            guard let shallowPath, let data = try? Data(contentsOf: URL(fileURLWithPath: shallowPath.trimmingCharacters(in: .whitespacesAndNewlines))) else { return "" }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
        let replacements = (try? await runGit(arguments: ["for-each-ref", "--format=%(refname):%(objectname)", "refs/replace"], in: url)) ?? ""
        let fingerprintData = tips.joined(separator: "\n") + "|shallow:\(shallow)|\(shallowDigest)|\(replacements)"
        let fingerprint = SHA256.hash(data: Data(fingerprintData.utf8)).map { String(format: "%02x", $0) }.joined()
        var result = RepositoryStatistics()
        if !tips.isEmpty {
            let log = try await runGit(arguments: ["log", "--all", "--format=%at%x09%an%x09%ae", "--no-show-signature"], in: url)
            let worker = Task.detached(priority: .utility) { RepositoryStatisticsAggregator.aggregate(log, query: query) }
            result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        }
        try Task.checkCancellation()
        result.calculatedAt = now
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
