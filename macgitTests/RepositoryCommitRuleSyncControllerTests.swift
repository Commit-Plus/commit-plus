// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class RepositoryCommitRuleSyncControllerTests: XCTestCase {
    func testCloudPreferenceAppliesWithoutReplacingOtherRepoSettings() async throws {
        let suite = "commit-rule-sync-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = RepoSettingsStore(userDefaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/repo")
        var settings = RepoSettings.defaults(currentBranch: "main", remotes: ["origin"])
        settings.userName = "Local author"
        local.update(for: url.path, settings: settings)
        let controller = RepositoryCommitRuleSyncController(defaults: defaults, localStore: local, resolver: CommitRuleTestIdentity())
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
        let suite = "commit-rule-sync-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = RepoSettingsStore(userDefaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/repo")
        let first = RepositoryCommitRuleSyncController(defaults: defaults, localStore: local, resolver: CommitRuleTestIdentity())
        first.markChanged(false, uid: "user-a", repositoryURL: url)
        let cloud = CommitRuleTestCloud(value: true)
        cloud.failSave = true
        let failure = await first.reconcile(repositoryURL: url, uid: "user-a", cloud: cloud) { _ in XCTFail("Must not overwrite local edit") }
        XCTAssertNotNil(failure)
        cloud.failSave = false
        let second = RepositoryCommitRuleSyncController(defaults: defaults, localStore: local, resolver: CommitRuleTestIdentity())
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
    init(value: Bool?) { self.value = value }
    func load(identity: RepositoryBookmarkIdentity, uid: String) async throws -> Bool? {
        loads += 1
        return value
    }
    func save(_ skipWarnings: Bool, identity: RepositoryBookmarkIdentity, uid: String) async throws {
        if failSave { throw CloudSettingsError.invalidDocument }
        saves.append(skipWarnings)
        value = skipWarnings
    }
}
