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

import FirebaseFirestore
import XCTest
@testable import macgit

@MainActor
final class GitFlowConfigurationSyncTests: XCTestCase {
    func testCloudDocumentUsesExactDurableConfigurationSchema() throws {
        let configuration = GitFlowConfiguration(
            isEnabled: true,
            mainBranch: "trunk",
            developBranch: "integration",
            featurePrefix: "feat/",
            bugfixPrefix: "fix/",
            releasePrefix: "ship/",
            hotfixPrefix: "urgent/",
            defaultStartDestination: .newWorktree,
            topicFinishStrategy: .rebaseFastForward,
            createReleaseTagOnFinish: false,
            createHotfixTagOnFinish: true
        )
        let cloudConfiguration = GitFlowCloudConfiguration(
            configuration: configuration,
            canonicalKey: "github.com/openai/codex"
        )
        let timestamp = Timestamp(date: Date(timeIntervalSince1970: 123))

        let document = GitFlowCloudConfigurationDocument.encode(
            cloudConfiguration,
            updatedAt: timestamp
        )

        XCTAssertEqual(
            Set(document.keys),
            [
                "schemaVersion",
                "canonicalKey",
                "isEnabled",
                "mainBranch",
                "developBranch",
                "featurePrefix",
                "bugfixPrefix",
                "releasePrefix",
                "hotfixPrefix",
                "topicFinishStrategy",
                "createReleaseTagOnFinish",
                "createHotfixTagOnFinish",
                "updatedAt",
            ]
        )
        XCTAssertNil(document["defaultStartDestination"])
        XCTAssertNil(document["repositoryPath"])
        XCTAssertNil(document["recoveryCheckpoint"])
        XCTAssertEqual(
            try GitFlowCloudConfigurationDocument.decode(document),
            cloudConfiguration
        )

        var documentWithLocalState = document
        documentWithLocalState["defaultStartDestination"] = "newWorktree"
        XCTAssertThrowsError(
            try GitFlowCloudConfigurationDocument.decode(documentWithLocalState)
        )
    }

    func testApplyingCloudConfigurationPreservesMachineStartDestination() {
        let local = GitFlowConfiguration(
            isEnabled: false,
            defaultStartDestination: .newWorktree
        )
        let cloud = GitFlowCloudConfiguration(
            configuration: GitFlowConfiguration(
                isEnabled: true,
                mainBranch: "trunk",
                developBranch: "next",
                topicFinishStrategy: .rebaseFastForward
            ),
            canonicalKey: "github.com/openai/codex"
        )

        let merged = cloud.applying(to: local)

        XCTAssertTrue(merged.isEnabled)
        XCTAssertEqual(merged.mainBranch, "trunk")
        XCTAssertEqual(merged.developBranch, "next")
        XCTAssertEqual(merged.topicFinishStrategy, .rebaseFastForward)
        XCTAssertEqual(merged.defaultStartDestination, .newWorktree)
    }

    func testNewCloneDownloadsCloudConfigurationIntoLocalCache() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let identity = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "git@github.com:openai/codex.git"
            )
        )
        let cloudConfiguration = GitFlowCloudConfiguration(
            configuration: GitFlowConfiguration(
                isEnabled: true,
                mainBranch: "trunk",
                developBranch: "next",
                featurePrefix: "feat/"
            ),
            canonicalKey: identity.canonicalKey
        )
        let cloudStore = FakeGitFlowConfigurationCloudStore(
            configuration: cloudConfiguration
        )
        let controller = GitFlowConfigurationSyncController(
            cloudStore: cloudStore,
            identityResolver: FakeRepositoryRemoteIdentityResolver(identity: identity),
            dataStore: fixture.store
        )

        let outcome = await controller.reconcile(
            repositoryURL: repositoryURL,
            fallbackConfiguration: GitFlowConfiguration(
                defaultStartDestination: .newWorktree
            ),
            uid: "user-a"
        )

        let resolved = try XCTUnwrap(outcome.configuration)
        XCTAssertEqual(resolved.mainBranch, "trunk")
        XCTAssertEqual(resolved.featurePrefix, "feat/")
        XCTAssertEqual(resolved.defaultStartDestination, .newWorktree)
        XCTAssertNil(outcome.warningMessage)
        let cachedConfiguration = await GitFlowConfigurationStore().configuration(
            in: repositoryURL
        )
        XCTAssertEqual(cachedConfiguration, resolved)
    }

    func testExistingLocalConfigurationSeedsMissingCloudDocument() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let identity = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "https://github.com/openai/codex.git"
            )
        )
        let localConfiguration = GitFlowConfiguration(
            isEnabled: true,
            mainBranch: "trunk",
            developBranch: "next",
            defaultStartDestination: .newWorktree
        )
        try await GitFlowConfigurationStore().save(localConfiguration, in: repositoryURL)
        let cloudStore = FakeGitFlowConfigurationCloudStore(configuration: nil)
        let controller = GitFlowConfigurationSyncController(
            cloudStore: cloudStore,
            identityResolver: FakeRepositoryRemoteIdentityResolver(identity: identity),
            dataStore: fixture.store
        )

        let outcome = await controller.reconcile(
            repositoryURL: repositoryURL,
            fallbackConfiguration: GitFlowConfiguration(),
            uid: "user-a"
        )

        XCTAssertNil(outcome.configuration)
        XCTAssertNil(outcome.warningMessage)
        XCTAssertEqual(cloudStore.savedRepositoryID, identity.documentID)
        XCTAssertEqual(cloudStore.savedConfiguration?.mainBranch, "trunk")
        XCTAssertEqual(cloudStore.savedConfiguration?.developBranch, "next")
    }

    func testFailedSignedInSaveRetriesLocalConfigurationBeforeReadingCloud() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let identity = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "https://github.com/openai/codex.git"
            )
        )
        let cloudStore = FakeGitFlowConfigurationCloudStore(
            configuration: GitFlowCloudConfiguration(
                configuration: GitFlowConfiguration(
                    isEnabled: true,
                    mainBranch: "old-main",
                    developBranch: "old-develop"
                ),
                canonicalKey: identity.canonicalKey
            )
        )
        cloudStore.shouldFailSave = true
        let controller = GitFlowConfigurationSyncController(
            cloudStore: cloudStore,
            identityResolver: FakeRepositoryRemoteIdentityResolver(identity: identity),
            dataStore: fixture.store
        )
        let localConfiguration = GitFlowConfiguration(
            isEnabled: true,
            mainBranch: "trunk",
            developBranch: "next"
        )

        let warning = try await controller.save(
            localConfiguration,
            repositoryURL: repositoryURL,
            uid: "user-a"
        )
        XCTAssertNotNil(warning)

        cloudStore.shouldFailSave = false
        let outcome = await controller.reconcile(
            repositoryURL: repositoryURL,
            fallbackConfiguration: GitFlowConfiguration(),
            uid: "user-a"
        )

        XCTAssertNil(outcome.configuration)
        XCTAssertNil(outcome.warningMessage)
        XCTAssertEqual(cloudStore.configurationRequestCount, 0)
        XCTAssertEqual(cloudStore.savedConfiguration?.mainBranch, "trunk")
        XCTAssertEqual(cloudStore.savedConfiguration?.developBranch, "next")
        XCTAssertTrue(try fixture.store.values(String.self, in: "gitFlowPending").isEmpty)
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-git-flow-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        return repositoryURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let standardError = Pipe()
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            throw GitError.commandFailed(message)
        }
    }
}

@MainActor
private final class FakeGitFlowConfigurationCloudStore: GitFlowConfigurationCloudStore {
    var configurationValue: GitFlowCloudConfiguration?
    var savedConfiguration: GitFlowCloudConfiguration?
    var savedRepositoryID: String?
    var shouldFailSave = false
    var configurationRequestCount = 0

    init(configuration: GitFlowCloudConfiguration?) {
        configurationValue = configuration
    }

    func configuration(
        repositoryID: String,
        uid: String
    ) async throws -> GitFlowCloudConfiguration? {
        configurationRequestCount += 1
        return configurationValue
    }

    func save(
        _ configuration: GitFlowCloudConfiguration,
        repositoryID: String,
        uid: String
    ) async throws {
        if shouldFailSave {
            throw FakeGitFlowConfigurationCloudStoreError.saveFailed
        }
        savedConfiguration = configuration
        savedRepositoryID = repositoryID
    }
}

private enum FakeGitFlowConfigurationCloudStoreError: Error {
    case saveFailed
}

private struct FakeRepositoryRemoteIdentityResolver: RepositoryRemoteIdentityResolving {
    let identityValue: RepositoryBookmarkIdentity

    init(identity: RepositoryBookmarkIdentity) {
        identityValue = identity
    }

    func identity(in repositoryURL: URL) async -> RepositoryBookmarkIdentity? {
        identityValue
    }
}
