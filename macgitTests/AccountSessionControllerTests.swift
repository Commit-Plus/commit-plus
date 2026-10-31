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
final class AccountSessionControllerTests: XCTestCase {
    func testGuestRemainsAvailableWhenFirebaseIsMissing() {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: nil),
            bootstrapStatus: .missingConfiguration
        )

        XCTAssertEqual(controller.state, .guest)
        XCTAssertFalse(controller.cloudFeaturesAvailable)
    }

    func testEmailSignInPublishesAccount() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured
        )

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.welcomeState, .neutral)
    }

    func testLiveEntitlementUpdatesWelcomeForFreeAndProAccounts() async {
        let account = Self.account
        let entitlements = WelcomeFakeEntitlementProvider()
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured,
            entitlementProvider: entitlements
        )

        await controller.signIn(email: "a@example.com", password: "secret12")
        XCTAssertEqual(controller.welcomeState, .neutral)

        entitlements.send(.free)
        XCTAssertEqual(controller.welcomeState, .free)

        entitlements.send(AccountEntitlement(
            plan: .pro,
            access: .active,
            billingStatus: .active
        ))
        XCTAssertEqual(controller.welcomeState, .pro)
    }

    func testCachedFreeEntitlementDoesNotLabelWelcomeUntilLiveResolution() async {
        let account = Self.account
        let entitlements = WelcomeFakeEntitlementProvider()
        let cache = WelcomeFakeEntitlementCache(values: [
            account.uid: CachedAccountEntitlement(entitlement: .free, updatedAt: .now)
        ])
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured,
            entitlementProvider: entitlements,
            entitlementCache: cache
        )

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertEqual(controller.entitlement, .free)
        XCTAssertEqual(controller.welcomeState, .neutral)
    }

    func testDismissedWelcomeDoesNotReturnAfterDelayedEntitlement() async {
        let account = Self.account
        let entitlements = WelcomeFakeEntitlementProvider()
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured,
            entitlementProvider: entitlements
        )

        await controller.signIn(email: "a@example.com", password: "secret12")
        controller.dismissWelcome()
        entitlements.send(.free)

        XCTAssertNil(controller.welcomeState)
    }

    func testControllerPresentedAuthenticationStaysOpenForWelcomeThenCloses() async {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: Self.account),
            bootstrapStatus: .configured
        )
        controller.presentAuthentication(.signIn)

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertEqual(controller.presentedSheet, .authentication(.signIn))
        XCTAssertEqual(controller.welcomeState, .neutral)

        controller.dismissWelcome()

        XCTAssertNil(controller.presentedSheet)
        XCTAssertNil(controller.welcomeState)
    }

    func testCreateAccountKeepsControllerSheetModeForWelcome() async {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: Self.account),
            bootstrapStatus: .configured
        )
        controller.presentAuthentication(.createAccount)

        await controller.createAccount(email: "a@example.com", password: "secret12")

        XCTAssertEqual(controller.presentedSheet, .authentication(.createAccount))
        XCTAssertEqual(controller.welcome?.host, .controllerSheet)
    }

    func testLocalSheetWelcomeBelongsToItsHostAndEndsWhenItDisappears() async {
        let host = AccountWelcomeHost.localSheet(UUID())
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: Self.account),
            bootstrapStatus: .configured
        )

        await controller.signIn(email: "a@example.com", password: "secret12", welcomeHost: host)

        XCTAssertEqual(controller.welcome?.host, host)
        XCTAssertNil(controller.presentedSheet)

        controller.authenticationSheetDidDisappear(host: .localSheet(UUID()))
        XCTAssertNotNil(controller.welcome)

        controller.authenticationSheetDidDisappear(host: host)
        XCTAssertNil(controller.welcome)
    }

    func testPresentingAuthenticationDiscardsUndisplayedWelcome() async {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: Self.account),
            bootstrapStatus: .configured
        )
        await controller.signIn(email: "a@example.com", password: "secret12")

        controller.presentAuthentication(.signIn)

        XCTAssertNil(controller.welcome)
        XCTAssertEqual(controller.presentedSheet, .authentication(.signIn))
    }

    func testReauthenticatingSignedInAccountDoesNotShowWelcome() async {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: Self.account, signInResult: Self.account),
            bootstrapStatus: .configured
        )
        controller.presentReauthentication()

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertNil(controller.welcome)
        XCTAssertNil(controller.presentedSheet)
    }

    func testDeviceRecoveryFromLocalSheetClosesDeviceLimitAndWelcomesInHost() async {
        let host = AccountWelcomeHost.localSheet(UUID())
        let metadata = Self.metadata
        let access = FakeDeviceAccessProvider(claimResult: .limitReached(limit: 1))
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: Self.account),
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: access,
            deviceSessionCache: FakeDeviceSessionCache()
        )

        await controller.signIn(email: "a@example.com", password: "secret12", welcomeHost: host)
        XCTAssertEqual(controller.presentedSheet, .deviceLimit)
        XCTAssertNil(controller.welcome)

        access.claimResult = .active(limit: 1, device: Self.device(metadata: metadata))
        await controller.retryDeviceActivation()

        XCTAssertEqual(controller.account, Self.account)
        XCTAssertNil(controller.presentedSheet)
        XCTAssertEqual(controller.welcome?.host, host)
    }

    func testDeviceRecoveryFromControllerSheetReplacesDeviceLimitWithWelcome() async {
        let metadata = Self.metadata
        let access = FakeDeviceAccessProvider(claimResult: .limitReached(limit: 1))
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: Self.account),
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: access,
            deviceSessionCache: FakeDeviceSessionCache()
        )
        controller.presentAuthentication(.signIn)

        await controller.signIn(email: "a@example.com", password: "secret12")
        access.claimResult = .active(limit: 1, device: Self.device(metadata: metadata))
        await controller.retryDeviceActivation()

        XCTAssertEqual(controller.presentedSheet, .authentication(.signIn))
        XCTAssertEqual(controller.welcome?.host, .controllerSheet)
    }

    func testCancelledDeviceRecoveryDropsPendingWelcome() async {
        let metadata = Self.metadata
        let access = FakeDeviceAccessProvider(claimResult: .limitReached(limit: 1))
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: Self.account),
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: access,
            deviceSessionCache: FakeDeviceSessionCache()
        )

        await controller.signIn(email: "a@example.com", password: "secret12")
        controller.cancelDeviceActivation()
        access.claimResult = .active(limit: 1, device: Self.device(metadata: metadata))
        await controller.retryDeviceActivation()

        XCTAssertNil(controller.account)
        XCTAssertNil(controller.welcome)
    }

    func testSignInFailureReturnsToGuestAndPublishesMessage() async {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(error: .invalidCredentials),
            bootstrapStatus: .configured
        )

        await controller.signIn(email: "a@example.com", password: "wrong")

        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(controller.errorMessage, "The email or password is incorrect.")
        XCTAssertNil(controller.welcomeState)
    }

    func testSignOutReturnsToGuest() {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        controller.signOut()

        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(auth.signOutCallCount, 1)
        XCTAssertNil(controller.welcomeState)
    }

    func testPresentAccountsRequestsAccountsSettings() {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: nil),
            bootstrapStatus: .configured
        )

        let navigation = expectation(forNotification: .showAppSettings, object: nil) { notification in
            notification.userInfo?["section"] as? String == AppSettingsSection.accounts.rawValue
        }
        controller.presentAccounts()
        wait(for: [navigation], timeout: 1)
        XCTAssertNil(controller.presentedSheet)
    }

    func testPresentProfileRequestsProfileSettings() {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: nil), bootstrapStatus: .configured
        )
        let navigation = expectation(forNotification: .showAppSettings, object: nil) { notification in
            notification.userInfo?["section"] as? String == AppSettingsSection.profile.rawValue
        }
        controller.presentProfile()
        wait(for: [navigation], timeout: 1)
        XCTAssertNil(controller.presentedSheet)
    }

    func testSuccessfulAccountDeletionReturnsToGuest() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(auth.deleteAccountCallCount, 1)
        XCTAssertEqual(controller.state, .guest)
    }

    func testFailedAccountDeletionKeepsAuthenticatedState() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account, error: .networkUnavailable)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertEqual(controller.errorMessage, "Connect to the internet and try again.")
    }

    func testRecentAuthenticationFailureKeepsAccountAndOffersRecovery() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account, error: .requiresRecentAuthentication)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertTrue(controller.requiresRecentAuthentication)
    }

    func testOpenAccountOnWebUsesAuthenticatedProfileURL() async throws {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let profileURL = try XCTUnwrap(
            URL(string: "http://localhost:3000/session?next=/account/profile#token=test-token")
        )
        let provider = FakeWebAccountSessionProvider(
            urls: [.profile: profileURL]
        )
        var openedURLs: [URL] = []
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: account),
            bootstrapStatus: .configured,
            webAccountSessionProvider: provider,
            openWebURL: { url in
                openedURLs.append(url)
                return true
            }
        )

        await controller.openAccountOnWeb()

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(openedURLs, [profileURL])
        XCTAssertFalse(controller.isOpeningAccountOnWeb)
        XCTAssertNil(controller.openingWebDestination)
        XCTAssertNil(controller.errorMessage)
    }

    func testOpenPricingOnWebUsesAuthenticatedPricingURL() async throws {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let pricingURL = try XCTUnwrap(
            URL(string: "http://localhost:3000/session?next=/pricing#token=test-token")
        )
        let provider = FakeWebAccountSessionProvider(
            urls: [.pricing: pricingURL]
        )
        var openedURLs: [URL] = []
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: account),
            bootstrapStatus: .configured,
            webAccountSessionProvider: provider,
            openWebURL: { url in
                openedURLs.append(url)
                return true
            }
        )

        await controller.openPricingOnWeb()

        XCTAssertEqual(provider.requestedDestinations, [.pricing])
        XCTAssertEqual(openedURLs, [pricingURL])
        XCTAssertFalse(controller.isOpeningAccountOnWeb)
        XCTAssertNil(controller.openingWebDestination)
        XCTAssertNil(controller.errorMessage)
    }

    func testOpenPricingFailureLeavesRetryableError() async {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: Self.account),
            bootstrapStatus: .configured,
            webAccountSessionProvider: FakeWebAccountSessionProvider(urls: [:])
        )

        await controller.openPricingOnWeb()

        XCTAssertEqual(controller.errorMessage, "Commit+ Cloud returned an invalid web sign-in response.")
        XCTAssertFalse(controller.isOpeningAccountOnWeb)
        XCTAssertNil(controller.openingWebDestination)
    }

    func testDeviceClaimPublishesAccountOnlyAfterFirestoreActivation() async {
        let account = Self.account
        let metadata = Self.metadata
        let device = Self.device(metadata: metadata)
        let auth = FakeAccountAuth(signInResult: account)
        let access = FakeDeviceAccessProvider(
            claimResult: .active(limit: 1, device: device)
        )
        let controller = AccountSessionController(
            auth: auth,
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: access,
            deviceSessionCache: FakeDeviceSessionCache()
        )

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertEqual(access.claimedMetadata, [metadata])
        XCTAssertEqual(access.claimedUIDs, [account.uid])
        XCTAssertEqual(controller.deviceAccessState, .active(limit: 1, device: device, verification: .live))
        XCTAssertEqual(controller.welcomeState, .neutral)
    }

    func testDeviceLimitDoesNotExposeAuthenticatedAccount() async {
        let account = Self.account
        let metadata = Self.metadata
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: FakeDeviceAccessProvider(
                claimResult: .limitReached(limit: 1)
            ),
            deviceSessionCache: FakeDeviceSessionCache()
        )

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertNil(controller.account)
        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(controller.presentedSheet, .deviceLimit)
        XCTAssertEqual(controller.deviceAccessState, .limitReached(limit: 1))
        XCTAssertNil(controller.welcomeState)
    }

    func testDeviceLimitCanOpenAuthenticatedWebManagement() async throws {
        let account = Self.account
        let profileURL = try XCTUnwrap(
            URL(string: "https://commit-plus.com/session?next=/account/profile?section%3Ddevices#token=test")
        )
        let webProvider = FakeWebAccountSessionProvider(urls: [.devices: profileURL])
        var openedURLs: [URL] = []
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured,
            webAccountSessionProvider: webProvider,
            openWebURL: { openedURLs.append($0); return true },
            deviceIdentity: FakeDeviceIdentity(metadata: Self.metadata),
            deviceAccessProvider: FakeDeviceAccessProvider(claimResult: .limitReached(limit: 1)),
            deviceSessionCache: FakeDeviceSessionCache()
        )

        await controller.signIn(email: "a@example.com", password: "secret12")
        await controller.openDeviceManagementOnWeb()

        XCTAssertEqual(webProvider.requestedDestinations, [.devices])
        XCTAssertEqual(openedURLs, [profileURL])
        XCTAssertNil(controller.account)
    }

    func testInitialOfflineFailureRestoresPreviouslyVerifiedDeviceCache() async {
        let account = Self.account
        let cache = FakeDeviceSessionCache()
        cache.save(
            CachedAccountDeviceSession(
                uid: account.uid,
                deviceID: Self.metadata.deviceID,
                verifiedAt: .now
            )
        )
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: account),
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: Self.metadata),
            deviceAccessProvider: FakeDeviceAccessProvider(
                claimError: DeviceAccessError(message: "Offline")
            ),
            deviceSessionCache: cache
        )

        for _ in 0..<10 where controller.account == nil {
            await Task.yield()
        }

        XCTAssertEqual(controller.state, .authenticated(account))
        guard case .active(limit: 1, _, verification: .cached) = controller.deviceAccessState else {
            return XCTFail("Expected cached device access after an offline startup failure.")
        }
        XCTAssertNil(controller.errorMessage)
        XCTAssertNil(controller.presentedSheet)
        XCTAssertNil(controller.welcomeState)
    }

    func testRemoteRevocationStopsCloudSessionAndPreservesGuestUse() async {
        let account = Self.account
        let metadata = Self.metadata
        let device = Self.device(metadata: metadata)
        let auth = FakeAccountAuth(signInResult: account)
        let access = FakeDeviceAccessProvider(
            claimResult: .active(limit: 1, device: device)
        )
        let controller = AccountSessionController(
            auth: auth,
            bootstrapStatus: .configured,
            deviceIdentity: FakeDeviceIdentity(metadata: metadata),
            deviceAccessProvider: access,
            deviceSessionCache: FakeDeviceSessionCache()
        )
        await controller.signIn(email: "a@example.com", password: "secret12")

        access.emit(.revoked(.replaced))

        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(controller.deviceAccessState, .revoked(.replaced))
        XCTAssertEqual(auth.signOutCallCount, 1)
        XCTAssertEqual(controller.errorMessage, AccountDeviceRevocationReason.replaced.message)
    }

    private static let account = AccountSnapshot(
        uid: "u-device",
        email: "a@example.com",
        displayName: nil,
        providerIDs: ["password"]
    )

    private static let metadata = AccountDeviceMetadata(
        deviceID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        modelFamily: "MacBook Pro",
        osVersion: "15.6.0",
        appVersion: "1.0"
    )

    private static func device(
        id: String = metadata.deviceID,
        metadata: AccountDeviceMetadata? = nil
    ) -> AccountDevice {
        let metadata = metadata ?? AccountDeviceMetadata(
            deviceID: id,
            modelFamily: "MacBook Air",
            osVersion: "15.6.0",
            appVersion: "1.0"
        )
        return AccountDevice(
            id: metadata.deviceID,
            modelFamily: metadata.modelFamily,
            osVersion: metadata.osVersion,
            appVersion: metadata.appVersion,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 1),
            lastSeenAt: Date(timeIntervalSince1970: 2),
            revokedAt: nil,
            revokedReason: nil
        )
    }
}

@MainActor
private final class FakeWebAccountSessionProvider: WebAccountSessionProviding {
    let urls: [WebAccountDestination: URL]
    private(set) var requestedDestinations: [WebAccountDestination] = []

    var requestCount: Int {
        requestedDestinations.count
    }

    init(urls: [WebAccountDestination: URL]) {
        self.urls = urls
    }

    func signInURL(for destination: WebAccountDestination) async throws -> URL {
        requestedDestinations.append(destination)
        guard let url = urls[destination] else {
            throw WebAccountSessionError.invalidServerResponse
        }
        return url
    }
}

private final class FakeAccountAuth: AccountAuthenticating {
    var currentAccount: AccountSnapshot?
    var signOutCallCount = 0
    var deleteAccountCallCount = 0

    private let signInResult: AccountSnapshot?
    private let error: AccountAuthError?

    init(
        current: AccountSnapshot? = nil,
        signInResult: AccountSnapshot? = nil,
        error: AccountAuthError? = nil
    ) {
        currentAccount = current
        self.signInResult = signInResult
        self.error = error
    }

    func signIn(email: String, password: String) async throws -> AccountSnapshot {
        if let error { throw error }
        return try XCTUnwrap(signInResult)
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

    func sendPasswordReset(email: String) async throws {
        if let error { throw error }
    }

    func deleteAccount() async throws {
        if let error { throw error }
        deleteAccountCallCount += 1
        currentAccount = nil
    }

    func signOut() throws {
        if let error { throw error }
        signOutCallCount += 1
        currentAccount = nil
    }
}

@MainActor
private struct FakeDeviceIdentity: DeviceIdentityProviding {
    let metadata: AccountDeviceMetadata

    func currentDevice() throws -> AccountDeviceMetadata { metadata }
}

@MainActor
private final class FakeDeviceAccessProvider: DeviceAccessProviding {
    var claimResult: DeviceActivationResult?
    var claimError: Error?
    private(set) var claimedMetadata: [AccountDeviceMetadata] = []
    private(set) var claimedUIDs: [String] = []
    private(set) var releasedDeviceIDs: [String] = []
    private var onChange: (@MainActor (AccountDeviceObservationState) -> Void)?

    init(claimResult: DeviceActivationResult) {
        self.claimResult = claimResult
        claimError = nil
    }

    init(claimError: Error) {
        claimResult = nil
        self.claimError = claimError
    }

    func claim(uid: String, metadata: AccountDeviceMetadata) async throws -> DeviceActivationResult {
        claimedUIDs.append(uid)
        claimedMetadata.append(metadata)
        if let claimError { throw claimError }
        return try XCTUnwrap(claimResult)
    }

    func release(uid: String, deviceID: String) async throws {
        releasedDeviceIDs.append(deviceID)
    }

    func observeCurrentDevice(
        uid: String,
        deviceID: String,
        onChange: @escaping @MainActor (AccountDeviceObservationState) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) -> ObservationToken {
        self.onChange = onChange
        return TestDeviceObservationToken()
    }

    func emit(_ state: AccountDeviceObservationState) {
        onChange?(state)
    }
}

private final class TestDeviceObservationToken: ObservationToken {
    func cancel() {}
}

@MainActor
private final class WelcomeFakeEntitlementProvider: EntitlementProviding {
    private var onChange: ((AccountEntitlement) -> Void)?

    func load(uid: String) async throws -> AccountEntitlement { .free }

    func observe(
        uid: String,
        onChange: @escaping (AccountEntitlement) -> Void,
        onError: @escaping (String) -> Void
    ) -> ObservationToken {
        self.onChange = onChange
        return TestDeviceObservationToken()
    }

    func send(_ entitlement: AccountEntitlement) {
        onChange?(entitlement)
    }
}

@MainActor
private final class WelcomeFakeEntitlementCache: EntitlementCaching {
    private var values: [String: CachedAccountEntitlement]

    init(values: [String: CachedAccountEntitlement]) {
        self.values = values
    }

    func cachedEntitlement(for uid: String) -> CachedAccountEntitlement? { values[uid] }

    func save(_ cachedEntitlement: CachedAccountEntitlement, for uid: String) {
        values[uid] = cachedEntitlement
    }

    func removeEntitlement(for uid: String) {
        values.removeValue(forKey: uid)
    }
}

@MainActor
private final class FakeDeviceSessionCache: AccountDeviceSessionCaching {
    private var sessions: [String: CachedAccountDeviceSession] = [:]

    func session(for uid: String) -> CachedAccountDeviceSession? { sessions[uid] }
    func save(_ session: CachedAccountDeviceSession) { sessions[session.uid] = session }
    func removeSession(for uid: String) { sessions.removeValue(forKey: uid) }
}
