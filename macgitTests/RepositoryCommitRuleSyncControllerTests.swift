// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class RepositoryCommitRuleSyncControllerTests: XCTestCase {
    func testCloudPreferenceAppliesWithoutReplacingOtherRepoSettings() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let local = RepoSettingsStore(dataStore: fixture.store)
        let url = URL(fileURLWithPath: "/tmp/repo")
        var settings = RepoSettings.defaults(currentBranch: "main", remotes: ["origin"])
        settings.userName = "Local author"
        try await local.update(for: url.path, settings: settings)
        let controller = RepositoryCommitRuleSyncController(localStore: local, resolver: CommitRuleTestIdentity())
        let cloud = CommitRuleTestCloud(value: true)
        var applied: Bool?
        let warning = await controller.reconcile(repositoryURL: url, uid: "user-a", cloud: cloud) { applied = $0 }
        XCTAssertNil(warning)
        XCTAssertEqual(applied, true)
        let loaded = local.settings(for: url.path, currentBranch: nil, remotes: [])
        XCTAssertTrue(loaded.skipProtectedBranchCommitWarnings)
        XCTAssertEqual(loaded.userName, "Local author")
        XCTAssertEqual(cloud.saves, [])
    }

    func testPendingOfflineChoiceSurvivesControllerRecreationAndWinsOverCloud() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let local = RepoSettingsStore(dataStore: fixture.store)
        let url = URL(fileURLWithPath: "/tmp/repo")
        let first = RepositoryCommitRuleSyncController(localStore: local, resolver: CommitRuleTestIdentity())
        try await first.markChanged(false, uid: "user-a", repositoryURL: url)
        let cloud = CommitRuleTestCloud(value: true)
        cloud.failSave = true
        let failure = await first.reconcile(repositoryURL: url, uid: "user-a", cloud: cloud) { _ in XCTFail("Must not overwrite local edit") }
        XCTAssertNotNil(failure)
        cloud.failSave = false
        let second = RepositoryCommitRuleSyncController(localStore: local, resolver: CommitRuleTestIdentity())
        let warning = await second.reconcile(repositoryURL: url, uid: "user-a", cloud: cloud) { _ in XCTFail("Must upload pending edit") }
        XCTAssertNil(warning)
        XCTAssertEqual(cloud.value, false)
    }

    func testSignedOutDoesNotAccessCloud() async {
        let cloud = CommitRuleTestCloud(value: true)
        let controller = RepositoryCommitRuleSyncController(resolver: CommitRuleTestIdentity())
        _ = await controller.reconcile(repositoryURL: URL(fileURLWithPath: "/tmp/repo"), uid: nil, cloud: cloud) { _ in XCTFail() }
        XCTAssertEqual(cloud.loads, 0)
        XCTAssertTrue(cloud.saves.isEmpty)
    }

    func testLocalEditWhileCloudLoadsWinsAndPreservesOtherSettings() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let local = RepoSettingsStore(dataStore: fixture.store)
        let url = URL(fileURLWithPath: "/tmp/repo")
        let cloud = CommitRuleTestCloud(value: true)
        cloud.onLoad = {
            var settings = RepoSettings.defaults(currentBranch: "work", remotes: ["upstream"])
            settings.userName = "Changed while loading"
            settings.skipProtectedBranchCommitWarnings = false
            try await local.update(for: url.path, settings: settings, pendingCommitRuleUID: "user-a")
        }
        let controller = RepositoryCommitRuleSyncController(localStore: local, resolver: CommitRuleTestIdentity())
        let warning = await controller.reconcile(repositoryURL: url, uid: "user-a", cloud: cloud) { _ in
            XCTFail("An old cloud value must not replace a local edit")
        }
        XCTAssertNil(warning)
        XCTAssertEqual(cloud.saves, [false])
        XCTAssertEqual(local.settings(for: url.path, currentBranch: nil, remotes: []).userName, "Changed while loading")
        XCTAssertTrue(try fixture.store.values(Bool.self, in: "commitRulePending").isEmpty)
    }
}

private struct CommitRuleTestIdentity: RepositoryRemoteIdentityResolving {
    func identity(in repositoryURL: URL) async -> RepositoryBookmarkIdentity? {
        RepositoryBookmarkIdentity.resolve(remoteURLString: "git@github.com:team/repo.git")
    }
}

@MainActor
private final class CommitRuleTestCloud: RepositoryCommitRuleCloudStore {
    var value: Bool?
    var saves: [Bool] = []
    var loads = 0
    var failSave = false
    var onLoad: (() async throws -> Void)?
    init(value: Bool?) { self.value = value }
    func load(identity: RepositoryBookmarkIdentity, uid: String) async throws -> Bool? {
        loads += 1
        try await onLoad?()
        return value
    }
    func save(_ skipWarnings: Bool, identity: RepositoryBookmarkIdentity, uid: String) async throws {
        if failSave { throw CloudSettingsError.invalidDocument }
        saves.append(skipWarnings)
        value = skipWarnings
    }
}
