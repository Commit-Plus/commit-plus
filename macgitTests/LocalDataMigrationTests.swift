// SPDX-License-Identifier: AGPL-3.0-or-later
import SQLite3
import XCTest
@testable import macgit

@MainActor
final class LocalDataMigrationTests: XCTestCase {
    func testImportsRelatedRecordsAndPreservesIDsAndLegacyBackup() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let prefix = "dev.thanhtran.macgit."
        let identity = try XCTUnwrap(RepositoryBookmarkIdentity.resolve(remoteURLString: "git@github.com:team/repo.git"))
        let bookmark = RepositoryBookmark(identity: identity)
        let account = makeAccount()
        let settings = RepoSettings(defaultPullBranch: "trunk")
        let ssh = GitProviderSSHKey(path: "/Users/test/.ssh/work")
        let encodedAccounts = try JSONEncoder().encode([account])
        fixture.defaults.set(try JSONEncoder().encode([bookmark]), forKey: prefix + "repositoryBookmarks.items")
        fixture.defaults.set([bookmark.id: "/tmp/repo"], forKey: prefix + "repositoryBookmarks.localPaths")
        fixture.defaults.set([bookmark.id], forKey: prefix + "repositoryBookmarks.pendingUploads")
        fixture.defaults.set(["deleted-bookmark"], forKey: prefix + "repositoryBookmarks.pendingDeletes")
        fixture.defaults.set(encodedAccounts, forKey: prefix + "localGitProviderAccounts")
        fixture.defaults.set(try JSONEncoder().encode([account]), forKey: prefix + "localGitProviderAccountPendingDeletions")
        fixture.defaults.set(["user-a": ["github|github.com|42"]], forKey: prefix + "localGitProviderAccountSyncedIdentities")
        fixture.defaults.set("original-owner", forKey: prefix + "localGitProviderAccountOwnerID")
        fixture.defaults.set(try JSONEncoder().encode(["/tmp/repo": settings]), forKey: prefix + "repoSettings")
        fixture.defaults.set(["remote": account.id], forKey: prefix + "providerAccountPreferences")
        fixture.defaults.set(try JSONEncoder().encode(ssh), forKey: GitProviderSSHKeyStoreKey.storageKey(for: account))
        fixture.defaults.set(["user-a|/tmp/repo": false], forKey: prefix + "repositoryCommitRules.pending")
        fixture.defaults.set(["user-a|remote"], forKey: prefix + "gitFlowConfiguration.pendingUploads")
        fixture.defaults.set("dark", forKey: "appearance")

        try await fixture.store.prepare()
        let reopened = try await fixture.reopen()
        XCTAssertEqual(try reopened.value(RepositoryBookmark.self, in: "bookmarks", id: bookmark.id), bookmark)
        XCTAssertEqual(try reopened.value(String.self, in: "bookmarkPaths", id: bookmark.id), "/tmp/repo")
        XCTAssertNotNil(try reopened.value(String.self, in: "bookmarkUploads", id: bookmark.id))
        XCTAssertNotNil(try reopened.value(String.self, in: "bookmarkDeletes", id: "deleted-bookmark"))
        XCTAssertEqual(try reopened.value(GitProviderAccount.self, in: "providerAccounts", id: account.id), account)
        XCTAssertEqual(try reopened.value(GitProviderAccount.self, in: "providerDeletions", id: account.id), account)
        XCTAssertEqual(try reopened.value([String].self, in: "providerSyncedIdentities", id: "user-a"), ["github|github.com|42"])
        XCTAssertEqual(try reopened.value(RepoSettings.self, in: "repoSettings", id: "/tmp/repo"), settings)
        XCTAssertEqual(try reopened.value(String.self, in: "providerPreferences", id: "remote"), account.id)
        XCTAssertEqual(try reopened.value(GitProviderSSHKey.self, in: "sshPaths", id: GitProviderSSHKeyStoreKey.storageKey(for: account)), ssh)
        XCTAssertEqual(try reopened.value(Bool.self, in: "commitRulePending", id: "user-a|/tmp/repo"), false)
        XCTAssertNotNil(try reopened.value(String.self, in: "gitFlowPending", id: "user-a|remote"))
        XCTAssertEqual(SQLiteGitProviderAccountLocalStore(dataStore: reopened, defaults: fixture.defaults).accountOwnerID, "original-owner")
        XCTAssertEqual(fixture.defaults.data(forKey: prefix + "localGitProviderAccounts"), encodedAccounts)
        XCTAssertEqual(fixture.defaults.string(forKey: "appearance"), "dark")
        XCTAssertTrue(try reopened.values(String.self, in: "appearance").isEmpty)
    }

    func testCompletedImportDoesNotResurrectDeletedAccountFromDefaults() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let account = makeAccount()
        fixture.defaults.set(try JSONEncoder().encode([account]), forKey: "dev.thanhtran.macgit.localGitProviderAccounts")
        try await fixture.store.prepare()
        let accounts = SQLiteGitProviderAccountLocalStore(dataStore: fixture.store, defaults: fixture.defaults)
        _ = try await accounts.delete(accountID: account.id)
        let reopened = try await fixture.reopen()
        XCTAssertNil(try reopened.value(GitProviderAccount.self, in: "providerAccounts", id: account.id))
        XCTAssertEqual(try reopened.value(GitProviderAccount.self, in: "providerDeletions", id: account.id), account)
        // Stale or subsequently damaged defaults must no longer be consulted.
        fixture.defaults.set(Data("broken".utf8), forKey: "dev.thanhtran.macgit.localGitProviderAccounts")
        _ = try await fixture.reopen()
    }

    func testCorruptLegacyDataLeavesImportRetryableAndDoesNotDiscardOriginal() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let key = "dev.thanhtran.macgit.repoSettings"
        let damaged = Data("{broken".utf8)
        fixture.defaults.set(damaged, forKey: key)
        do { try await fixture.store.prepare(); XCTFail("Corrupt user data must not become an empty store") }
        catch { XCTAssertFalse(fixture.store.isReady) }
        XCTAssertEqual(fixture.defaults.data(forKey: key), damaged)
        let settings = RepoSettings(defaultPullBranch: "recovered")
        fixture.defaults.set(try JSONEncoder().encode(["/tmp/repo": settings]), forKey: key)
        try await fixture.store.prepare()
        XCTAssertEqual(try fixture.store.value(RepoSettings.self, in: "repoSettings", id: "/tmp/repo"), settings)
    }

    func testAccountDeleteRollsBackMetadataLinksAndTombstoneOnDiskFailure() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let account = makeAccount()
        let accounts = SQLiteGitProviderAccountLocalStore(dataStore: fixture.store, defaults: fixture.defaults)
        try await accounts.save(account)
        try await GitProviderAccountPreferenceStore(dataStore: fixture.store).update(accountID: account.id, forPreferenceKey: "remote")
        let keys = SQLiteGitProviderSSHKeyStore(dataStore: fixture.store)
        try await keys.saveKey(GitProviderSSHKey(path: "/tmp/key"), for: account)
        try execute("CREATE TRIGGER fail_delete BEFORE INSERT ON records WHEN NEW.collection = 'providerDeletions' BEGIN SELECT RAISE(ABORT, 'test disk failure'); END", url: fixture.databaseURL)
        do { _ = try await accounts.delete(accountID: account.id); XCTFail("Write should fail") }
        catch { }
        XCTAssertEqual(try accounts.accounts(), [account])
        XCTAssertTrue(try accounts.pendingDeletions().isEmpty)
        let reopened = try await fixture.reopen()
        XCTAssertEqual(try reopened.value(GitProviderAccount.self, in: "providerAccounts", id: account.id), account)
        XCTAssertEqual(try reopened.value(String.self, in: "providerPreferences", id: "remote"), account.id)
        XCTAssertNotNil(try reopened.value(GitProviderSSHKey.self, in: "sshPaths", id: GitProviderSSHKeyStoreKey.storageKey(for: account)))
        try execute("DROP TRIGGER fail_delete", url: fixture.databaseURL)
        _ = try await accounts.delete(accountID: account.id)
        XCTAssertNil(try keys.key(for: account))
        XCTAssertTrue(try fixture.store.values(String.self, in: "providerPreferences").isEmpty)
        XCTAssertEqual(try accounts.pendingDeletions(), [account])
    }

    func testFailedImportRollsBackRowsAndMarkerThenRetries() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        let engine = LocalSQLiteDatabase(url: fixture.databaseURL)
        let needsImport = try await engine.needsLegacyImport()
        XCTAssertTrue(needsImport)
        try execute("CREATE TRIGGER fail_import BEFORE INSERT ON migrations BEGIN SELECT RAISE(ABORT, 'import failure'); END", url: fixture.databaseURL)
        fixture.defaults.set(try JSONEncoder().encode([makeAccount()]), forKey: "dev.thanhtran.macgit.localGitProviderAccounts")
        do { try await fixture.store.prepare(); XCTFail("Import should fail") }
        catch { }
        let rows = try await engine.load(importing: nil)
        XCTAssertTrue(rows.isEmpty)
        try execute("DROP TRIGGER fail_import", url: fixture.databaseURL)
        try await fixture.store.prepare()
        XCTAssertEqual(try fixture.store.values(GitProviderAccount.self, in: "providerAccounts").count, 1)
    }

    func testConcurrentTransactionsPreserveBothUpdates() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let first = Task { try await fixture.store.transaction { try $0.set(1, in: "counter", id: "first") } }
        let second = Task { try await fixture.store.transaction { try $0.set(2, in: "counter", id: "second") } }
        try await first.value
        try await second.value
        let reopened = try await fixture.reopen()
        XCTAssertEqual(try reopened.values(Int.self, in: "counter"), ["first": 1, "second": 2])
    }

    func testRepositorySettingsAndPendingRuleCommitTogether() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        var settings = RepoSettings(defaultPullBranch: "main")
        settings.skipProtectedBranchCommitWarnings = true
        try await RepoSettingsStore(dataStore: fixture.store).update(for: "/tmp/repo", settings: settings, pendingCommitRuleUID: "user-a")
        let reopened = try await fixture.reopen()
        XCTAssertEqual(try reopened.value(RepoSettings.self, in: "repoSettings", id: "/tmp/repo"), settings)
        XCTAssertEqual(try reopened.value(Bool.self, in: "commitRulePending", id: "user-a|/tmp/repo"), true)
        XCTAssertNil(try reopened.value(Bool.self, in: "commitRulePending", id: "user-b|/tmp/repo"))
    }

    func testBookmarkRemovalRollsBackAllRelatedRowsOnFailure() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let identity = try XCTUnwrap(RepositoryBookmarkIdentity.resolve(remoteURLString: "git@github.com:team/repo.git"))
        let bookmark = RepositoryBookmark(identity: identity)
        try await fixture.store.transaction { transaction in
            try transaction.set(bookmark, in: "bookmarks", id: bookmark.id)
            try transaction.set("/tmp/repo", in: "bookmarkPaths", id: bookmark.id)
            try transaction.set("pending", in: "bookmarkUploads", id: bookmark.id)
        }
        let controller = RepositoryBookmarkController(cloudStore: nil, dataStore: fixture.store)
        try controller.load()
        try execute("CREATE TRIGGER fail_bookmark BEFORE INSERT ON records WHEN NEW.collection = 'bookmarkDeletes' BEGIN SELECT RAISE(ABORT, 'test failure'); END", url: fixture.databaseURL)
        await controller.removeBookmark(bookmark)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(controller.bookmarks, [bookmark])
        XCTAssertEqual(controller.localURL(for: bookmark)?.path, "/tmp/repo")
        let reopened = try await fixture.reopen()
        XCTAssertNotNil(try reopened.value(RepositoryBookmark.self, in: "bookmarks", id: bookmark.id))
        XCTAssertEqual(try reopened.value(String.self, in: "bookmarkUploads", id: bookmark.id), "pending")
        XCTAssertNil(try reopened.value(String.self, in: "bookmarkDeletes", id: bookmark.id))
    }

    func testBookmarkCloudFailureKeepsDeletionAcrossReopenAndStaleSnapshot() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let identity = try XCTUnwrap(RepositoryBookmarkIdentity.resolve(remoteURLString: "git@github.com:team/repo.git"))
        let bookmark = RepositoryBookmark(identity: identity)
        try await fixture.store.transaction { transaction in
            try transaction.set(bookmark, in: "bookmarks", id: bookmark.id)
            try transaction.set("/tmp/repo", in: "bookmarkPaths", id: bookmark.id)
        }
        let cloud = MigrationBookmarkCloud(bookmarks: [bookmark])
        let controller = RepositoryBookmarkController(cloudStore: cloud, dataStore: fixture.store)
        let account = AccountSnapshot(uid: "user-a", email: nil, displayName: nil, providerIDs: [])
        await controller.updateAccount(account)
        await controller.removeBookmark(bookmark)
        XCTAssertTrue(controller.bookmarks.isEmpty)
        XCTAssertNotNil(controller.errorMessage)
        let reopened = try await fixture.reopen()
        let second = RepositoryBookmarkController(cloudStore: cloud, dataStore: reopened)
        await second.updateAccount(account)
        XCTAssertTrue(second.bookmarks.isEmpty)
        XCTAssertNil(second.localURL(for: bookmark))
        XCTAssertNotNil(try reopened.value(String.self, in: "bookmarkDeletes", id: bookmark.id))
    }

    private func execute(_ sql: String, url: URL) throws {
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK, let db = connection else { throw LocalDataError.notReady }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "TestSQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }

    private func makeAccount() -> GitProviderAccount {
        GitProviderAccount(id: "original-account-id", macgitUID: "original-owner", provider: .github,
                           hostURL: URL(string: "https://github.com")!, providerUserID: "42", username: "test",
                           displayName: nil, avatarURL: nil, scopes: [], permissions: [:], tokenStatus: .valid,
                           connectedAt: Date(timeIntervalSince1970: 100), lastValidatedAt: nil)
    }
}

@MainActor
private final class MigrationBookmarkCloud: RepositoryBookmarkCloudStore {
    let storedBookmarks: [RepositoryBookmark]
    init(bookmarks: [RepositoryBookmark]) { storedBookmarks = bookmarks }
    func bookmarks(uid: String) async throws -> [RepositoryBookmark] { storedBookmarks }
    func save(_ bookmark: RepositoryBookmark, uid: String) async throws { }
    func delete(bookmarkID: String, uid: String) async throws { throw LocalDataError.notReady }
    func observe(uid: String, onChange: @escaping (Result<[RepositoryBookmark], Error>) -> Void) -> ObservationToken {
        MigrationObservationToken()
    }
}

private final class MigrationObservationToken: ObservationToken {
    func cancel() { }
}
