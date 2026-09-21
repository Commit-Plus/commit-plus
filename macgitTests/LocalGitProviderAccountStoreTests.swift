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

import XCTest
@testable import macgit

@MainActor
final class LocalGitProviderAccountStoreTests: XCTestCase {
    func testSignedOutStoreUsesLocalAccounts() async throws {
        let localAccount = makeAccount(id: "local", ownerID: "local-owner", providerUserID: "1")
        let localStore = FakeLocalProviderAccountStore(accounts: [localAccount])
        let store = LocalFirstGitProviderAccountStore(localStore: localStore, cloudStore: nil)

        try await store.updateCloudAccount(uid: nil)
        let accounts = try await store.accounts()

        XCTAssertEqual(accounts, [localAccount])
    }

    func testSignInMergesCloudIntoLocalAndMirrorsLocalToCurrentUID() async throws {
        let localAccount = makeAccount(id: "local", ownerID: "local-owner", providerUserID: "1")
        let cloudAccount = makeAccount(id: "cloud", ownerID: "firebase-user", providerUserID: "2")
        let localStore = FakeLocalProviderAccountStore(accounts: [localAccount])
        let cloudStore = FakeCloudProviderAccountStore(accounts: [cloudAccount])
        let store = LocalFirstGitProviderAccountStore(localStore: localStore, cloudStore: cloudStore)

        try await store.updateCloudAccount(uid: "firebase-user")
        let accounts = try await store.accounts()

        XCTAssertEqual(Set(accounts.map(\.providerUserID)), ["1", "2"])
        XCTAssertEqual(Set(cloudStore.savedAccounts.map(\.providerUserID)), ["1", "2"])
        XCTAssertTrue(cloudStore.savedAccounts.allSatisfy { $0.macgitUID == "firebase-user" })
    }

    func testLocalAccountWinsWhenCloudHasSameProviderIdentity() async throws {
        var localAccount = makeAccount(id: "local", ownerID: "local-owner", providerUserID: "1")
        localAccount.username = "local-name"
        var cloudAccount = makeAccount(id: "cloud", ownerID: "firebase-user", providerUserID: "1")
        cloudAccount.username = "cloud-name"
        let localStore = FakeLocalProviderAccountStore(accounts: [localAccount])
        let cloudStore = FakeCloudProviderAccountStore(accounts: [cloudAccount])
        let store = LocalFirstGitProviderAccountStore(localStore: localStore, cloudStore: cloudStore)

        try await store.updateCloudAccount(uid: "firebase-user")
        let accounts = try await store.accounts()

        XCTAssertEqual(accounts, [localAccount])
        XCTAssertEqual(cloudStore.savedAccounts.last?.username, "local-name")
        XCTAssertTrue(cloudStore.deletedAccountIDs.contains("cloud"))
    }

    func testCloudLoadFailureDoesNotRemoveLocalAccounts() async throws {
        let localAccount = makeAccount(id: "local", ownerID: "local-owner", providerUserID: "1")
        let localStore = FakeLocalProviderAccountStore(accounts: [localAccount])
        let cloudStore = FakeCloudProviderAccountStore(accounts: [], loadError: TestCloudError.failed)
        let store = LocalFirstGitProviderAccountStore(localStore: localStore, cloudStore: cloudStore)

        try await store.updateCloudAccount(uid: "firebase-user")
        let accounts = try await store.accounts()

        XCTAssertEqual(accounts, [localAccount])
    }

    func testCloudSaveFailureDoesNotRollbackLocalSave() async throws {
        let localStore = FakeLocalProviderAccountStore(accounts: [])
        let cloudStore = FakeCloudProviderAccountStore(accounts: [], saveError: TestCloudError.failed)
        let store = LocalFirstGitProviderAccountStore(localStore: localStore, cloudStore: cloudStore)
        try await store.updateCloudAccount(uid: "firebase-user")
        let account = makeAccount(id: "local", ownerID: "local-owner", providerUserID: "1")

        try await store.save(account)
        let accounts = try await store.accounts()

        XCTAssertEqual(accounts, [account])
    }

    func testFailedCloudDeleteKeepsLocalTombstoneAndDoesNotRestoreAccount() async throws {
        let account = makeAccount(id: "local", ownerID: "local-owner", providerUserID: "1")
        let localStore = FakeLocalProviderAccountStore(accounts: [account])
        let cloudStore = FakeCloudProviderAccountStore(
            accounts: [account],
            deleteError: TestCloudError.failed
        )
        let store = LocalFirstGitProviderAccountStore(localStore: localStore, cloudStore: cloudStore)
        try await store.updateCloudAccount(uid: "firebase-user")

        try await store.delete(accountID: account.id)
        try await store.updateCloudAccount(uid: "firebase-user")
        let accounts = try await store.accounts()

        XCTAssertTrue(accounts.isEmpty)
        XCTAssertEqual(try localStore.pendingDeletions(), [account])
    }

    func testRemoteDeletionRemovesPreviouslySyncedLocalMetadata() async throws {
        let account = makeAccount(id: "local", ownerID: "local-owner", providerUserID: "1")
        let localStore = FakeLocalProviderAccountStore(accounts: [account])
        let cloudStore = FakeCloudProviderAccountStore(accounts: [account])
        let store = LocalFirstGitProviderAccountStore(localStore: localStore, cloudStore: cloudStore)
        try await store.updateCloudAccount(uid: "firebase-user")
        cloudStore.accountsToLoad = []

        try await store.updateCloudAccount(uid: "firebase-user")
        let accounts = try await store.accounts()

        XCTAssertTrue(accounts.isEmpty)
    }

    func testSyncBookkeepingFailureDoesNotReportDurableAccountSaveAsFailed() async throws {
        let local = FakeLocalProviderAccountStore(accounts: [])
        let cloud = FakeCloudProviderAccountStore(accounts: [])
        let store = LocalFirstGitProviderAccountStore(localStore: local, cloudStore: cloud)
        try await store.updateCloudAccount(uid: "firebase-user")
        local.syncedKeysError = TestCloudError.failed
        let account = makeAccount(id: "local", ownerID: "local-owner", providerUserID: "1")
        try await store.save(account)
        let saved = try await store.accounts()
        XCTAssertEqual(saved, [account])
    }

    private func makeAccount(id: String, ownerID: String, providerUserID: String) -> GitProviderAccount {
        GitProviderAccount(
            id: id,
            macgitUID: ownerID,
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: providerUserID,
            username: "octocat-\(providerUserID)",
            displayName: nil,
            avatarURL: nil,
            scopes: ["repo"],
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }
}

@MainActor
private final class FakeLocalProviderAccountStore: GitProviderAccountLocalStore {
    let accountOwnerID = "local-owner"
    private var storedAccounts: [GitProviderAccount]
    private var deletions: [GitProviderAccount] = []
    private var syncedKeysByUID: [String: Set<String>] = [:]
    var syncedKeysError: Error?

    init(accounts: [GitProviderAccount]) {
        storedAccounts = accounts
    }

    func accounts() throws -> [GitProviderAccount] {
        storedAccounts
    }

    func save(_ account: GitProviderAccount) throws {
        storedAccounts.removeAll { $0.id == account.id }
        storedAccounts.append(account)
    }

    func delete(accountID: String) throws -> GitProviderAccount? {
        let account = storedAccounts.first { $0.id == accountID }
        storedAccounts.removeAll { $0.id == accountID }
        if let account {
            deletions.removeAll { $0.id == account.id }
            deletions.append(account)
        }
        return account
    }

    func remove(accountID: String) throws {
        storedAccounts.removeAll { $0.id == accountID }
    }

    func pendingDeletions() throws -> [GitProviderAccount] {
        deletions
    }

    func clearPendingDeletion(_ account: GitProviderAccount) throws {
        deletions.removeAll { $0.id == account.id }
    }

    func syncedIdentityKeys(uid: String) -> Set<String> {
        syncedKeysByUID[uid] ?? []
    }

    func setSyncedIdentityKeys(_ keys: Set<String>, uid: String) throws {
        if let syncedKeysError { throw syncedKeysError }
        syncedKeysByUID[uid] = keys
    }
}

@MainActor
private final class FakeCloudProviderAccountStore: GitProviderAccountCloudStore {
    var accountsToLoad: [GitProviderAccount]
    private let loadError: Error?
    private let saveError: Error?
    private let deleteError: Error?
    private(set) var savedAccounts: [GitProviderAccount] = []
    private(set) var deletedAccountIDs: [String] = []

    init(
        accounts: [GitProviderAccount],
        loadError: Error? = nil,
        saveError: Error? = nil,
        deleteError: Error? = nil
    ) {
        accountsToLoad = accounts
        self.loadError = loadError
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func accounts(forMacgitUID uid: String) async throws -> [GitProviderAccount] {
        if let loadError { throw loadError }
        return accountsToLoad
    }

    func save(_ account: GitProviderAccount) async throws {
        if let saveError { throw saveError }
        savedAccounts.append(account)
    }

    func delete(accountID: String, macgitUID: String) async throws {
        if let deleteError { throw deleteError }
        deletedAccountIDs.append(accountID)
    }
}

private enum TestCloudError: Error {
    case failed
}
