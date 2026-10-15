// SPDX-License-Identifier: AGPL-3.0-or-later
// Standalone harness: compiles production catalog/SQLite/statistics sources without the app host.
import Foundation

// App bootstrap and unrelated legacy migrations are intentionally outside this harness.
enum FirebaseBootstrap { static let isRunningUnitTests = true }
enum LegacyLocalDataMigration {
    static func records(from defaults: UserDefaults) throws -> [String: [String: Data]] { [:] }
}

// Exercise the production detail/statistics extension using actual local Git fixtures.
actor GitStatusService {
    static let shared = GitStatusService()
    func runGit(arguments: [String], in directory: URL) async throws -> String {
        let process = Process()
        let output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GitFixture", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: error, as: UTF8.self)])
        }
        return String(decoding: data, as: UTF8.self)
    }
    func remoteURLs(in url: URL) async -> [String] { [] }
    func repoPickerStatus(in url: URL) async -> RepoPickerStatusSnapshot {
        .init(currentBranch: nil, changedFileCount: 0, behindCount: 0, aheadCount: 0, includesAheadBehind: true)
    }
}

@main
struct RepositoryCatalogChecks {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("CommitPlusCatalogChecks-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let suite = "CommitPlusCatalogChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = directory.appendingPathComponent("projects", isDirectory: true)
        let nested = root.appendingPathComponent("group", isDirectory: true)
        let repository = nested.appendingPathComponent("repo", isDirectory: true)
        let opened = Date(timeIntervalSince1970: 1000)
        var recent = RecentRepository(url: repository, lastOpened: opened)
        recent.name = "Preserved Name"
        let legacy = try JSONEncoder().encode([recent, recent])
        defaults.set(legacy, forKey: "dev.thanhtran.macgit.recentRepositories")
        defaults.set([root.path, nested.path, root.path], forKey: "dev.thanhtran.macgit.yourRepositoryFolders")
        let dataStore = LocalDataStore(databaseURL: directory.appendingPathComponent("catalog.sqlite"), userDefaults: defaults)
        let catalog = RepositoryCatalogStore(dataStore: dataStore, defaults: defaults)
        await catalog.ready()
        precondition(catalog.errorMessage == nil)
        precondition(catalog.snapshot.repositories.count == 1)
        precondition(catalog.snapshot.roots.count == 2)
        precondition(catalog.snapshot.repositories[0].name == "Preserved Name")
        precondition(catalog.snapshot.repositories[0].lastOpened == opened)
        precondition(defaults.data(forKey: "dev.thanhtran.macgit.recentRepositories") == legacy)
        let localID = catalog.snapshot.repositories[0].id

        await catalog.reconcile(root: root, repositories: [repository], error: nil)
        await catalog.reconcile(root: nested, repositories: [repository], error: nil)
        precondition(catalog.snapshot.memberships.count == 2)
        await catalog.reconcile(root: root, repositories: [], error: "Permission denied")
        precondition(catalog.snapshot.memberships.count == 2, "A failed scan must retain memberships")
        catalog.removeRoot(root)
        await catalog.ready()
        precondition(catalog.snapshot.memberships.count == 1)
        precondition(catalog.snapshot.repositories[0].id == localID)
        catalog.setProvider("github", bookmarkKey: "github.com/owner/repo", for: repository)
        await catalog.ready()
        catalog.removeRecent([RepositoryCatalogSnapshot.path(repository)])
        await catalog.ready()
        let reopened = RepositoryCatalogStore(dataStore: dataStore, defaults: defaults)
        await reopened.ready()
        precondition(reopened.snapshot.repositories[0].id == localID)
        precondition(reopened.snapshot.repositories[0].lastOpened == nil, "Legacy defaults must not resurrect removed recents")
        precondition(reopened.snapshot.repositories[0].provider == "github")
        precondition(reopened.snapshot.roots.count == 1)
        let relocated = directory.appendingPathComponent("relocated", isDirectory: true)
        reopened.relink(repository, to: relocated)
        await reopened.ready()
        precondition(reopened.snapshot.repositories.first { $0.path == RepositoryCatalogSnapshot.path(relocated) }?.id == localID)
        precondition(reopened.snapshot.memberships.isEmpty, "Relinking out of a root removes the obsolete membership")

        let scanner = YourRepositoriesStore(catalog: reopened)
        if case .homeFolder = scanner.addFolders([manager.homeDirectoryForCurrentUser]) {} else { preconditionFailure("Home must be rejected") }
        if case .homeFolder = scanner.addFolders([URL(fileURLWithPath: "/")]) {} else { preconditionFailure("Filesystem root must be rejected") }
        if case .duplicate = scanner.addFolders([nested]) {} else { preconditionFailure("Duplicate roots must be reported") }

        let scanDirectory = directory.appendingPathComponent("scan", isDirectory: true)
        let directoryRepo = scanDirectory.appendingPathComponent("one", isDirectory: true)
        let worktreeRepo = scanDirectory.appendingPathComponent("group/two", isDirectory: true)
        try manager.createDirectory(at: directoryRepo.appendingPathComponent(".git/nested/.git"), withIntermediateDirectories: true)
        try manager.createDirectory(at: worktreeRepo, withIntermediateDirectories: true)
        try Data("gitdir: elsewhere".utf8).write(to: worktreeRepo.appendingPathComponent(".git"))
        try manager.createSymbolicLink(at: scanDirectory.appendingPathComponent("loop"), withDestinationURL: scanDirectory)
        let found = YourRepositoriesStore.scanRepositories(in: [scanDirectory, scanDirectory.appendingPathComponent("group")])
        precondition(Set(found.map { $0.url.path }) == [directoryRepo.path, worktreeRepo.path])
        precondition(YourRepositoriesStore.scanRoot(directory.appendingPathComponent("missing")).error != nil)

        for index in 0..<25 { reopened.open(directory.appendingPathComponent("repo-\(index)")) }
        await reopened.ready()
        precondition(reopened.snapshot.repositories.filter { $0.lastOpened != nil }.count == 20)
        let knownDestination = directory.appendingPathComponent("repo-24")
        reopened.relink(relocated, to: knownDestination)
        await reopened.ready()
        precondition(reopened.record(for: knownDestination)?.id == localID)
        precondition(reopened.snapshot.repositories.filter { $0.path == RepositoryCatalogSnapshot.path(knownDestination) }.count == 1)
        let partialA = nested.appendingPathComponent("partial-a"), partialB = nested.appendingPathComponent("partial-b")
        await reopened.reconcile(root: nested, repositories: [partialA], error: nil)
        await reopened.reconcile(root: nested, repositories: [partialB], error: "One subfolder could not be read")
        precondition(reopened.snapshot.memberships.count == 2, "Partial scans add discoveries while retaining previous members")

        defaults.set(Data("invalid".utf8), forKey: "dev.thanhtran.macgit.recentRepositories")
        let corruptStore = LocalDataStore(databaseURL: directory.appendingPathComponent("corrupt.sqlite"), userDefaults: defaults)
        let corrupt = RepositoryCatalogStore(dataStore: corruptStore, defaults: defaults)
        await corrupt.ready()
        precondition(corrupt.errorMessage != nil)
        let markers = try await corruptStore.readValues(Bool.self, in: "repositoryCatalogMigrations")
        precondition(markers.isEmpty, "Failed imports must not mark migration complete")

        let formatter = ISO8601DateFormatter()
        let first = formatter.date(from: "2026-01-05T23:30:00Z")!
        let second = formatter.date(from: "2026-03-06T12:00:00Z")!
        let log = "\(first.timeIntervalSince1970)\tAlice\tALICE@example.com\n\(second.timeIntervalSince1970)\tAlice Renamed\talice@example.com\n"
        let stats = RepositoryStatisticsAggregator.aggregate(log, query: .init(timeZone: "UTC"))
        precondition(stats.total == 2 && stats.contributors.count == 1)
        precondition(stats.monthly.count == 3 && stats.monthly[1].count == 0)
        precondition(stats.hours.first(where: { $0.key == "23" })?.count == 1)
        precondition(stats.weekdays.first(where: { $0.key == "Mon" })?.count == 1)
        let filtered = RepositoryStatisticsAggregator.aggregate(log, query: .init(start: first, end: second, timeZone: "Asia/Ho_Chi_Minh"))
        precondition(filtered.total == 1, "Date range uses inclusive start and exclusive end")
        precondition(filtered.weekdays.first(where: { $0.key == "Tue" })?.count == 1)
        precondition(filtered.hours.first(where: { $0.key == "6" })?.count == 1)
        let empty = RepositoryStatisticsAggregator.aggregate("", query: .init(timeZone: "UTC"))
        precondition(empty.total == 0 && empty.monthly.isEmpty)

        let git = GitStatusService.shared
        let fixture = directory.appendingPathComponent("git-fixture", isDirectory: true)
        try manager.createDirectory(at: fixture, withIntermediateDirectories: true)
        _ = try await git.runGit(arguments: ["init", "-q"], in: fixture)
        _ = try await git.runGit(arguments: ["config", "user.name", "Fixture Author"], in: fixture)
        _ = try await git.runGit(arguments: ["config", "user.email", "fixture@example.test"], in: fixture)
        let fixtureID = UUID()
        let allTime = RepositoryStatisticsQuery(timeZone: "UTC")
        let unborn = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore, forceRefresh: true)
        precondition(unborn.total == 0)
        _ = try await git.runGit(arguments: ["commit", "--allow-empty", "-qm", "first", "--date=2026-01-05T23:30:00Z"], in: fixture)
        try Data("plain text".utf8).write(to: fixture.appendingPathComponent("README.txt"))
        try Data("# Working tree README".utf8).write(to: fixture.appendingPathComponent("README.md"))
        let detail = RepositoryDetailModel()
        await detail.load(fixture)
        precondition(detail.readme == "# Working tree README" && detail.readmeURL?.lastPathComponent == "README.md")
        let objectBytes = detail.size
        precondition((objectBytes ?? 0) > 0)
        try Data(repeating: 1, count: 1024 * 1024).write(to: fixture.appendingPathComponent("build-cache.bin"))
        try Data("# Uncommitted change".utf8).write(to: fixture.appendingPathComponent("README.md"))
        await detail.load(fixture)
        precondition(detail.readme == "# Uncommitted change")
        precondition(detail.size == objectBytes, "Working files and caches must not affect repository size")
        let sideCommit = try await git.runGit(arguments: ["commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "remote-only commit"], in: fixture).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await git.runGit(arguments: ["update-ref", "refs/remotes/origin/side", sideCommit], in: fixture)
        _ = try await git.runGit(arguments: ["tag", "side-tag", sideCommit], in: fixture)
        let overview = await git.repositoryInfo(in: fixture)
        precondition(overview.commits == 2, "Overview includes all refs and counts shared commits once")
        let linkedFixture = directory.appendingPathComponent("linked-detail-worktree")
        _ = try await git.runGit(arguments: ["worktree", "add", "--detach", linkedFixture.path, "HEAD"], in: fixture)
        await detail.load(fixture)
        let sharedBytes = detail.size
        let linkedDetail = RepositoryDetailModel()
        await linkedDetail.load(linkedFixture)
        precondition(linkedDetail.size == sharedBytes, "Linked worktrees measure the common Git object database")
        let one = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore, forceRefresh: true)
        precondition(one.total == 2 && one.fingerprint != unborn.fingerprint)
        let cached = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore)
        precondition(cached == one, "Unchanged refs/query should reuse the persisted aggregate")
        let originalBranch = try await git.runGit(arguments: ["symbolic-ref", "--short", "HEAD"], in: fixture).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await git.runGit(arguments: ["checkout", "-qb", "statistics-side", sideCommit], in: fixture)
        let switched = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore)
        precondition(switched == one, "Switching to a branch whose history is already included must reuse the aggregate")
        _ = try await git.runGit(arguments: ["checkout", "-q", originalBranch], in: fixture)
        let fetchedCommit = try await git.runGit(arguments: ["commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "fetched-only history"], in: fixture).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await git.runGit(arguments: ["update-ref", "refs/remotes/origin/fetched", fetchedCommit], in: fixture)
        let withinTTL = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore, now: one.calculatedAt.addingTimeInterval(6 * 60 * 60 - 1))
        precondition(withinTTL == one, "Commit/ref changes must not invalidate the six-hour cache")
        let expired = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore, now: one.calculatedAt.addingTimeInterval(6 * 60 * 60))
        precondition(expired.total == 3 && expired.calculatedAt != one.calculatedAt, "The cache expires at six hours")
        let fetched = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore, forceRefresh: true)
        precondition(fetched.total == 3 && fetched.fingerprint != one.fingerprint, "Manual reload bypasses the cache even when HEAD is unchanged")
        _ = try await git.runGit(arguments: ["update-ref", "-d", "refs/remotes/origin/fetched"], in: fixture)
        let removed = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore, forceRefresh: true)
        precondition(removed.total == 2 && removed.fingerprint == one.fingerprint, "Removing the last ref to history updates the aggregate")
        _ = try await git.runGit(arguments: ["commit", "--allow-empty", "-qm", "second", "--date=2026-03-06T12:00:00Z"], in: fixture)
        let two = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore, forceRefresh: true)
        precondition(two.total == 3 && two.fingerprint != one.fingerprint)
        _ = try await git.runGit(arguments: ["commit", "--amend", "--allow-empty", "-qm", "rewritten"], in: fixture)
        let rewritten = try await git.repositoryStatistics(in: fixture, query: allTime, repositoryID: fixtureID, cache: dataStore, forceRefresh: true)
        precondition(rewritten.total == 3 && rewritten.fingerprint != two.fingerprint)
        let shallowURL = directory.appendingPathComponent("shallow-fixture", isDirectory: true)
        _ = try await git.runGit(arguments: ["clone", "-q", "--depth=1", fixture.absoluteString, shallowURL.path], in: directory)
        let shallowID = UUID()
        let shallow = try await git.repositoryStatistics(in: shallowURL, query: allTime, repositoryID: shallowID, cache: dataStore, forceRefresh: true)
        precondition(shallow.total == 1 && shallow.isShallow)
        _ = try await git.runGit(arguments: ["fetch", "-q", "--deepen=1"], in: shallowURL)
        let deepened = try await git.repositoryStatistics(in: shallowURL, query: allTime, repositoryID: shallowID, cache: dataStore, forceRefresh: true)
        precondition(deepened.total == 2 && deepened.fingerprint != shallow.fingerprint)
        print("PASS: migration/idempotency/relink/overlapping roots/failed scans/recents/provider/corrupt rollback; Home/root/duplicate validation; real scanner/worktrees/symlink loop; working-tree README; author/date/timezone/empty statistics; real Git cache reuse, new HEAD, rewritten history and shallow deepening")
    }
}
