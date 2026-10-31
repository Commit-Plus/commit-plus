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
final class EntitlementGateTests: XCTestCase {
    private let account = AccountSnapshot(
        uid: "u1",
        email: "a@example.com",
        displayName: nil,
        providerIDs: ["password"]
    )

    func testExistingSessionStartsExactlyOneObservation() {
        let provider = FakeEntitlementProvider()
        _ = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )

        XCTAssertEqual(provider.observedUIDs, ["u1"])
    }

    func testSignInStartsObservationAndProUpdateChangesMenuPolicy() async {
        let provider = FakeEntitlementProvider()
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(signInResult: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )

        await controller.signIn(email: "a@example.com", password: "secret12")
        provider.send(.pro)

        XCTAssertEqual(provider.observedUIDs, ["u1"])
        XCTAssertTrue(controller.entitlement.hasProAccess)
        XCTAssertEqual(
            AccountMenuPolicy.actions(account: controller.account, entitlement: controller.entitlement),
            [.manageAccount, .manageAccountAndSubscription, .accounts, .syncStatus, .signOut]
        )
    }

    func testSignOutCancelsObservationAndResetsFree() {
        let provider = FakeEntitlementProvider()
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )
        provider.send(.pro)

        controller.signOut()

        XCTAssertEqual(provider.token.cancelCount, 1)
        XCTAssertEqual(controller.entitlement, .free)

        provider.send(.pro)
        XCTAssertEqual(controller.entitlement, .free)
    }

    func testListenerFailureKeepsLatestSessionEntitlement() {
        let provider = FakeEntitlementProvider()
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )
        provider.send(.pro)

        provider.fail("Firestore unavailable")

        XCTAssertEqual(controller.entitlement, .pro)
        XCTAssertTrue(controller.isUsingCachedEntitlement)
        XCTAssertEqual(controller.entitlementError, "Firestore unavailable")
    }

    func testCachedEntitlementLoadsBeforeFirestoreAndSurvivesListenerFailure() {
        let provider = FakeEntitlementProvider()
        let cachedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = FakeEntitlementCache(
            values: ["u1": CachedAccountEntitlement(entitlement: .pro, updatedAt: cachedAt)]
        )
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider,
            entitlementCache: cache
        )

        XCTAssertEqual(controller.entitlement, .pro)
        XCTAssertEqual(controller.entitlementLastUpdatedAt, cachedAt)
        XCTAssertTrue(controller.isUsingCachedEntitlement)

        provider.fail("Firestore unavailable")

        XCTAssertEqual(controller.entitlement, .pro)
        XCTAssertTrue(controller.isUsingCachedEntitlement)
        XCTAssertEqual(controller.entitlementError, "Firestore unavailable")
    }

    func testFirestoreUpdateReplacesAndPersistsCachedEntitlement() {
        let provider = FakeEntitlementProvider()
        let cache = FakeEntitlementCache()
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider,
            entitlementCache: cache
        )

        provider.send(.pro)

        XCTAssertEqual(cache.values["u1"]?.entitlement, .pro)
        XCTAssertEqual(controller.entitlement, .pro)
        XCTAssertFalse(controller.isUsingCachedEntitlement)
        XCTAssertNotNil(controller.entitlementLastUpdatedAt)
    }

    func testRefreshProfileReloadsAccountAndEntitlementFromServer() async {
        let refreshedAccount = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: "Updated Name",
            providerIDs: ["password"]
        )
        let auth = EntitlementFakeAuth(current: account)
        auth.refreshedAccount = refreshedAccount
        let provider = FakeEntitlementProvider()
        provider.loadResult = .pro
        let controller = AccountSessionController(
            auth: auth,
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )

        await controller.refreshProfile()

        XCTAssertEqual(controller.account, refreshedAccount)
        XCTAssertEqual(provider.loadedUIDs, ["u1"])
        XCTAssertEqual(controller.entitlement, .pro)
        XCTAssertFalse(controller.isRefreshingProfile)
        XCTAssertNil(controller.errorMessage)
    }

    func testSuccessfulAccountDeletionRemovesCachedEntitlement() async {
        let provider = FakeEntitlementProvider()
        let cache = FakeEntitlementCache(
            values: [
                "u1": CachedAccountEntitlement(
                    entitlement: .pro,
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ]
        )
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider,
            entitlementCache: cache
        )

        await controller.deleteAccount()

        XCTAssertNil(cache.values["u1"])
    }
}

private extension AccountEntitlement {
    static let pro = AccountEntitlement(
        plan: .pro,
        access: .active,
        billingStatus: .active,
        source: .adminTest
    )
}

@MainActor
private final class FakeEntitlementProvider: EntitlementProviding {
    let token = FakeObservationToken()
    var observedUIDs: [String] = []
    var loadedUIDs: [String] = []
    var loadResult: AccountEntitlement = .free
    private var onChange: ((AccountEntitlement) -> Void)?
    private var onError: ((String) -> Void)?

    func load(uid: String) async throws -> AccountEntitlement {
        loadedUIDs.append(uid)
        return loadResult
    }

    func observe(
        uid: String,
        onChange: @escaping (AccountEntitlement) -> Void,
        onError: @escaping (String) -> Void
    ) -> ObservationToken {
        observedUIDs.append(uid)
        self.onChange = onChange
        self.onError = onError
        return token
    }

    func send(_ entitlement: AccountEntitlement) {
        onChange?(entitlement)
    }

    func fail(_ message: String) {
        onError?(message)
    }
}

private final class FakeObservationToken: ObservationToken {
    private(set) var cancelCount = 0
    func cancel() { cancelCount += 1 }
}

@MainActor
private final class FakeEntitlementCache: EntitlementCaching {
    var values: [String: CachedAccountEntitlement]

    init(values: [String: CachedAccountEntitlement] = [:]) {
        self.values = values
    }

    func cachedEntitlement(for uid: String) -> CachedAccountEntitlement? {
        values[uid]
    }

    func save(_ cachedEntitlement: CachedAccountEntitlement, for uid: String) {
        values[uid] = cachedEntitlement
    }

    func removeEntitlement(for uid: String) {
        values.removeValue(forKey: uid)
    }
}

private final class EntitlementFakeAuth: AccountAuthenticating {
    var currentAccount: AccountSnapshot?
    private let signInResult: AccountSnapshot?
    var refreshedAccount: AccountSnapshot?

    init(current: AccountSnapshot? = nil, signInResult: AccountSnapshot? = nil) {
        currentAccount = current
        self.signInResult = signInResult
    }

    func refreshCurrentAccount() async throws -> AccountSnapshot {
        guard let refreshedAccount = refreshedAccount ?? currentAccount else {
            throw AccountAuthError.invalidCredentials
        }
        currentAccount = refreshedAccount
        return refreshedAccount
    }

    func signIn(email: String, password: String) async throws -> AccountSnapshot {
        guard let signInResult else { throw AccountAuthError.invalidCredentials }
        currentAccount = signInResult
        return signInResult
    }

    func createAccount(email: String, password: String) async throws -> AccountSnapshot {
        try await signIn(email: email, password: password)
    }

    func signInWithGoogle() async throws -> AccountSnapshot {
        try await signIn(email: "", password: "")
    }

    func completePendingLink(email: String, password: String) async throws -> AccountSnapshot {
        try await signIn(email: email, password: password)
    }

    func sendPasswordReset(email: String) async throws {}
    func deleteAccount() async throws { currentAccount = nil }

    func signOut() throws {
        currentAccount = nil
    }
}
