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

import AppKit
import Combine
import Foundation

@MainActor
final class AccountSessionController: ObservableObject {
    @Published private(set) var state: AccountSessionState
    @Published var presentedSheet: AccountSheet?
    private(set) weak var sheetPresentationWindow: NSWindow?
    @Published var errorMessage: String?
    @Published private(set) var passwordResetMessage: String?
    @Published private(set) var pendingLinkEmail: String?
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var requiresRecentAuthentication = false
    @Published private(set) var webSignInWindowNumber: Int?
    @Published private(set) var isOpeningAccountOnWeb = false
    @Published private(set) var openingWebDestination: WebAccountDestination?
    @Published private(set) var isRefreshingProfile = false
    @Published private(set) var entitlement: AccountEntitlement = .free
    @Published private(set) var entitlementError: String?
    @Published private(set) var entitlementLastUpdatedAt: Date?
    @Published private(set) var isUsingCachedEntitlement = false
    @Published private(set) var settingsSyncStatus: SettingsSyncStatus = .off
    @Published private(set) var deviceAccessState: AccountDeviceAccessState = .unavailable
    @Published private(set) var isUpdatingDeviceAccess = false

    let cloudFeaturesAvailable: Bool

    private let auth: AccountAuthenticating
    private let entitlementProvider: EntitlementProviding?
    private let entitlementCache: EntitlementCaching?
    private let webAccountSessionProvider: WebAccountSessionProviding?
    private let openWebURL: (URL) -> Bool
    private let appState: AppState
    private let settingsSyncService: SettingsSyncService?
    private let deviceIdentity: DeviceIdentityProviding?
    private let deviceAccessProvider: DeviceAccessProviding?
    private let deviceSessionCache: AccountDeviceSessionCaching?
    private var entitlementObservation: ObservationToken?
    private var deviceObservation: ObservationToken?
    private var settingsEligibilityTask: Task<Void, Never>?
    private var pendingTemporaryAccount: AccountSnapshot?
    private var currentDeviceMetadata: AccountDeviceMetadata?
    private var cancellables = Set<AnyCancellable>()

    var account: AccountSnapshot? {
        guard case .authenticated(let account) = state else { return nil }
        return account
    }

    var isLoading: Bool {
        state == .loading
    }

    var settingsSyncEnabled: Bool {
        appState.syncEnabled
    }

    var pendingCloudSettings: AppSettingsSnapshot? {
        guard case .needsInitialChoice(let snapshot) = settingsSyncStatus else { return nil }
        return snapshot
    }

    var localSettingsSnapshot: AppSettingsSnapshot {
        appState.snapshot
    }

    var settingsSyncStatusText: String {
        switch settingsSyncStatus {
        case .off: "Off"
        case .locked: "Sign In Required"
        case .starting: "Starting..."
        case .needsInitialChoice: "Choose Settings"
        case .syncing: "Syncing"
        case .paused: "Paused"
        case .failed: "Error"
        }
    }

    var settingsSyncDisplayText: String {
        guard account != nil else { return "Sign In Required" }
        guard settingsSyncEnabled else { return "Off" }

        switch settingsSyncStatus {
        case .off:
            return "Starting..."
        default:
            return settingsSyncStatusText
        }
    }

    var settingsSyncError: String? {
        guard case .failed(let message) = settingsSyncStatus else { return nil }
        return message
    }

    init(
        auth: AccountAuthenticating,
        bootstrapStatus: FirebaseBootstrapStatus,
        entitlementProvider: EntitlementProviding? = nil,
        entitlementCache: EntitlementCaching? = nil,
        webAccountSessionProvider: WebAccountSessionProviding? = nil,
        openWebURL: @escaping (URL) -> Bool = { _ in false },
        appState: AppState? = nil,
        settingsStore: CloudSettingsStore? = nil,
        deviceIdentity: DeviceIdentityProviding? = nil,
        deviceAccessProvider: DeviceAccessProviding? = nil,
        deviceSessionCache: AccountDeviceSessionCaching? = nil
    ) {
        self.auth = auth
        self.entitlementProvider = entitlementProvider
        self.entitlementCache = entitlementCache
        self.webAccountSessionProvider = webAccountSessionProvider
        self.deviceIdentity = deviceIdentity
        self.deviceAccessProvider = deviceAccessProvider
        self.deviceSessionCache = deviceSessionCache
        self.openWebURL = openWebURL
        let resolvedAppState = appState ?? AppState.shared
        self.appState = resolvedAppState
        if let settingsStore {
            settingsSyncService = SettingsSyncService(
                store: settingsStore,
                currentSnapshot: { resolvedAppState.snapshot },
                applySnapshot: { resolvedAppState.apply($0) },
                setSyncEnabled: { resolvedAppState.syncEnabled = $0 }
            )
        } else {
            settingsSyncService = nil
        }
        cloudFeaturesAvailable = bootstrapStatus == .configured
        let initialAccount = cloudFeaturesAvailable ? auth.currentAccount : nil
        if initialAccount != nil, deviceAccessProvider != nil, deviceIdentity != nil {
            state = .loading
            deviceAccessState = .unverified
        } else if let initialAccount {
            state = .authenticated(initialAccount)
        } else {
            state = .guest
        }

        bindSettingsSync()
        if let initialAccount, deviceAccessProvider == nil {
            startEntitlementObservation(for: initialAccount.uid)
        }
        scheduleSettingsSyncEligibilityUpdate()
        if let initialAccount, deviceAccessProvider != nil, deviceIdentity != nil {
            Task { [weak self] in
                await self?.restoreInitialDeviceSession(for: initialAccount)
            }
        }
    }

    func presentAuthentication(_ mode: AuthenticationMode) {
        errorMessage = nil
        passwordResetMessage = nil
        presentSheet(.authentication(mode), in: NSApp.keyWindow ?? NSApp.mainWindow)
    }

    func presentManageAccount() {
        presentSheet(.manageAccount, in: NSApp.keyWindow ?? NSApp.mainWindow)
    }

    func presentConnections() {
        presentSheet(.connections, in: NSApp.keyWindow ?? NSApp.mainWindow)
    }

    private func presentSheet(_ sheet: AccountSheet, in sourceWindow: NSWindow? = nil) {
        // Capture the owner once; focus can move to the sheet or another repository
        // while authentication and settings synchronization are in flight.
        var window = sourceWindow
            ?? (presentedSheet == nil ? nil : sheetPresentationWindow)
            ?? NSApp.keyWindow ?? NSApp.mainWindow
        while let parent = window?.sheetParent {
            window = parent
        }
        sheetPresentationWindow = window
        presentedSheet = sheet
    }

    func signIn(email: String, password: String) async {
        await authenticate { [auth] in
            try await auth.signIn(email: email, password: password)
        }
    }

    func createAccount(email: String, password: String) async {
        await authenticate { [auth] in
            try await auth.createAccount(email: email, password: password)
        }
    }

    func signInOnWeb() {
        guard cloudFeaturesAvailable, !isLoading, account == nil, pendingLinkEmail == nil else { return }
        errorMessage = nil
        do {
            let state = UUID().uuidString + UUID().uuidString
            guard var components = URLComponents(
                url: try CommitPlusWebConfiguration.baseURL().appending(path: "auth"),
                resolvingAgainstBaseURL: false
            ) else { throw WebAccountSessionError.invalidBaseURL }
            components.queryItems = [
                URLQueryItem(name: "app", value: "macgit"),
                URLQueryItem(name: "state", value: state)
            ]
            guard let url = components.url else { throw WebAccountSessionError.invalidBaseURL }
            UserDefaults.standard.set(state, forKey: "webSignInState")
            UserDefaults.standard.set(Date().addingTimeInterval(15 * 60), forKey: "webSignInExpiresAt")
            // A sign-in sheet can be the key window; route back to its owning scene.
            var originatingWindow = NSApp.keyWindow ?? NSApp.mainWindow
            while let parent = originatingWindow?.sheetParent {
                originatingWindow = parent
            }
            webSignInWindowNumber = originatingWindow?.windowNumber
            guard openWebURL(url) else { throw WebAccountSessionError.unableToOpenBrowser }
        } catch {
            cancelWebSignIn()
            errorMessage = Self.message(for: error)
        }
    }

    func handleWebSignInCallback(_ url: URL) async -> Bool {
        guard url.scheme?.lowercased() == "macgit", url.host?.lowercased() == "session" else { return false }
        guard !isLoading, account == nil else { return true }
        let signInWindow = NSApp.windows.first { $0.windowNumber == webSignInWindowNumber }
        presentSheet(.authentication(.signIn), in: signInWindow)
        guard url.path.isEmpty, url.user == nil, url.password == nil, url.port == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.filter({ $0.name == "token" }).count == 1,
              let expected = UserDefaults.standard.string(forKey: "webSignInState"),
              items.first(where: { $0.name == "state" })?.value == expected,
              let expiry = UserDefaults.standard.object(forKey: "webSignInExpiresAt") as? Date, expiry > Date(),
              let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty else {
            errorMessage = "This web sign-in link is invalid or expired. Choose Sign in on web again."
            return true
        }
        cancelWebSignIn()
        await authenticate { [auth] in
            try await auth.signIn(customToken: token)
        }
        return true
    }

    func cancelWebSignIn() {
        webSignInWindowNumber = nil
        UserDefaults.standard.removeObject(forKey: "webSignInState")
        UserDefaults.standard.removeObject(forKey: "webSignInExpiresAt")
    }

    func signInWithGoogle() async {
        await authenticate { [auth] in
            try await auth.signInWithGoogle()
        }
    }

    func completePendingLink(password: String) async {
        guard let email = pendingLinkEmail else { return }
        await authenticate { [auth] in
            try await auth.completePendingLink(email: email, password: password)
        }
    }

    func sendPasswordReset(email: String) async {
        guard cloudFeaturesAvailable else {
            errorMessage = AccountAuthError.cloudNotConfigured.localizedDescription
            return
        }

        let previousState = state
        state = .loading
        errorMessage = nil
        passwordResetMessage = nil
        do {
            try await auth.sendPasswordReset(email: email)
            state = previousState
            passwordResetMessage = "Password reset email sent."
        } catch {
            state = previousState
            errorMessage = Self.message(for: error)
        }
    }

    func signOut() {
        guard !isUpdatingDeviceAccess else { return }
        guard let deviceAccessProvider,
              let metadata = currentDeviceMetadata,
              let uid = account?.uid ?? pendingTemporaryAccount?.uid else {
            finishLocalSignOut()
            return
        }
        isUpdatingDeviceAccess = true
        Task { [weak self, deviceAccessProvider, metadata, uid] in
            guard let self else { return }
            var releaseWarning: String?
            do {
                try await deviceAccessProvider.release(uid: uid, deviceID: metadata.deviceID)
            } catch {
                releaseWarning = "Signed out on this Mac, but Commit+ could not release the remote slot. You can remove this Mac from your web profile. \(Self.message(for: error))"
            }
            finishLocalSignOut()
            errorMessage = releaseWarning
            isUpdatingDeviceAccess = false
        }
    }

    func deleteAccount() async {
        guard let account else { return }
        let deletedUID = account.uid
        isDeletingAccount = true
        errorMessage = nil
        requiresRecentAuthentication = false
        defer { isDeletingAccount = false }

        do {
            try await auth.deleteAccount()
            stopDeviceObservation()
            deviceSessionCache?.removeSession(for: deletedUID)
            stopEntitlementObservation()
            entitlementCache?.removeEntitlement(for: deletedUID)
            state = .guest
            presentedSheet = nil
            pendingLinkEmail = nil
            scheduleSettingsSyncEligibilityUpdate()
        } catch let error as AccountAuthError where error == .requiresRecentAuthentication {
            requiresRecentAuthentication = true
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func presentReauthentication() {
        presentAuthentication(.signIn)
    }

    func openAccountOnWeb() async {
        await openAuthenticatedWebPage(.profile)
    }

    func openDeviceManagementOnWeb() async {
        await openAuthenticatedWebPage(.devices)
    }

    func openPricingOnWeb() async {
        await openAuthenticatedWebPage(.pricing)
    }

    private func openAuthenticatedWebPage(_ destination: WebAccountDestination) async {
        guard !isOpeningAccountOnWeb,
              account != nil || pendingTemporaryAccount != nil,
              let webAccountSessionProvider else { return }
        openingWebDestination = destination
        isOpeningAccountOnWeb = true
        errorMessage = nil
        defer {
            isOpeningAccountOnWeb = false
            openingWebDestination = nil
        }

        do {
            let url = try await webAccountSessionProvider.signInURL(for: destination)
            guard openWebURL(url) else {
                throw WebAccountSessionError.unableToOpenBrowser
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func refreshProfile() async {
        guard let currentAccount = account, !isRefreshingProfile else { return }
        isRefreshingProfile = true
        errorMessage = nil
        entitlementError = nil
        defer { isRefreshingProfile = false }

        var refreshErrors: [String] = []

        do {
            let refreshedAccount = try await auth.refreshCurrentAccount()
            guard account?.uid == currentAccount.uid,
                  refreshedAccount.uid == currentAccount.uid else { return }
            state = .authenticated(refreshedAccount)
        } catch {
            refreshErrors.append(Self.message(for: error))
        }

        if let entitlementProvider {
            do {
                let refreshedEntitlement = try await entitlementProvider.load(uid: currentAccount.uid)
                guard account?.uid == currentAccount.uid else { return }
                applyEntitlement(refreshedEntitlement, uid: currentAccount.uid)
            } catch {
                let message = Self.message(for: error)
                entitlementError = message
            }
        }

        if !refreshErrors.isEmpty {
            errorMessage = refreshErrors.joined(separator: "\n")
        }
    }

    private func authenticate(
        operation: () async throws -> AccountSnapshot
    ) async {
        guard cloudFeaturesAvailable else {
            state = .guest
            errorMessage = AccountAuthError.cloudNotConfigured.localizedDescription
            return
        }

        cancelWebSignIn()
        let previousState = state
        state = .loading
        errorMessage = nil
        passwordResetMessage = nil
        do {
            let account = try await operation()
            if deviceAccessProvider != nil, deviceIdentity != nil {
                pendingTemporaryAccount = account
                await claimAndActivate(account: account)
            } else {
                completeAuthentication(account)
            }
        } catch let error as AccountAuthError {
            state = previousState == .loading ? .guest : previousState
            if case .needsExistingMethod(let email, _) = error {
                pendingLinkEmail = email
            }
            errorMessage = error.localizedDescription
        } catch {
            state = previousState == .loading ? .guest : previousState
            errorMessage = Self.message(for: error)
        }
    }

    func retryDeviceActivation() async {
        guard let pendingTemporaryAccount, !isUpdatingDeviceAccess else { return }
        await claimAndActivate(account: pendingTemporaryAccount)
    }

    func cancelDeviceActivation() {
        pendingTemporaryAccount = nil
        try? auth.signOut()
        state = .guest
        deviceAccessState = .unverified
        presentedSheet = nil
        errorMessage = nil
        scheduleSettingsSyncEligibilityUpdate()
    }

    private func restoreInitialDeviceSession(for initialAccount: AccountSnapshot) async {
        pendingTemporaryAccount = initialAccount
        await claimAndActivate(account: initialAccount)

        guard case .failed = deviceAccessState,
              let metadata = currentDeviceMetadata,
              deviceSessionCache?.session(for: initialAccount.uid)?.deviceID == metadata.deviceID else {
            return
        }
        let placeholder = Self.currentDevice(from: metadata)
        deviceAccessState = .active(limit: 1, device: placeholder, verification: .cached)
        errorMessage = nil
        presentedSheet = nil
        completeAuthentication(initialAccount)
        startDeviceObservation(uid: initialAccount.uid, metadata: metadata)
    }

    private func claimAndActivate(account: AccountSnapshot) async {
        guard let deviceAccessProvider, !isUpdatingDeviceAccess else { return }
        isUpdatingDeviceAccess = true
        errorMessage = nil
        deviceAccessState = .verifying
        defer { isUpdatingDeviceAccess = false }

        do {
            let metadata = try resolveCurrentDeviceMetadata()
            let result = try await deviceAccessProvider.claim(uid: account.uid, metadata: metadata)
            await finishActivationResult(result, temporaryAccount: account)
        } catch {
            state = .guest
            let message = Self.message(for: error)
            deviceAccessState = .failed(message: message, mayRetry: true)
            errorMessage = message
            presentSheet(.deviceLimit)
        }
    }

    private func finishActivationResult(
        _ result: DeviceActivationResult,
        temporaryAccount: AccountSnapshot
    ) async {
        switch result {
        case .limitReached(let limit):
            state = .guest
            deviceAccessState = .limitReached(limit: limit)
            presentSheet(.deviceLimit)
        case .active(let limit, let device):
            guard let metadata = currentDeviceMetadata else { return }
            deviceAccessState = .active(limit: limit, device: device, verification: .live)
            deviceSessionCache?.save(
                CachedAccountDeviceSession(
                    uid: temporaryAccount.uid,
                    deviceID: metadata.deviceID,
                    verifiedAt: .now
                )
            )
            pendingTemporaryAccount = nil
            completeAuthentication(temporaryAccount)
            startDeviceObservation(uid: temporaryAccount.uid, metadata: metadata)
        }
    }

    private func completeAuthentication(_ account: AccountSnapshot) {
        state = .authenticated(account)
        startEntitlementObservation(for: account.uid)
        requiresRecentAuthentication = false
        pendingLinkEmail = nil
        presentedSheet = nil
        scheduleSettingsSyncEligibilityUpdate()
    }

    private func resolveCurrentDeviceMetadata() throws -> AccountDeviceMetadata {
        if let currentDeviceMetadata { return currentDeviceMetadata }
        guard let deviceIdentity else {
            throw DeviceAccessError(message: "Commit+ device identity is unavailable.")
        }
        let metadata = try deviceIdentity.currentDevice()
        currentDeviceMetadata = metadata
        return metadata
    }

    private func startDeviceObservation(uid: String, metadata: AccountDeviceMetadata) {
        stopDeviceObservation()
        guard let deviceAccessProvider else { return }
        deviceObservation = deviceAccessProvider.observeCurrentDevice(
            uid: uid,
            deviceID: metadata.deviceID,
            onChange: { [weak self] observation in
                guard let self, account?.uid == uid else { return }
                switch observation {
                case .active(let device):
                    let limit = deviceAccessState.activeLimit ?? 1
                    deviceAccessState = .active(limit: limit, device: device, verification: .live)
                    deviceSessionCache?.save(
                        CachedAccountDeviceSession(uid: uid, deviceID: metadata.deviceID, verifiedAt: .now)
                    )
                case .revoked(let reason):
                    handleDeviceRevocation(reason, uid: uid)
                case .missing:
                    handleDeviceRevocation(nil, uid: uid)
                }
            },
            onError: { [weak self] message in
                guard self?.account?.uid == uid else { return }
                self?.errorMessage = message
            }
        )
    }

    private func handleDeviceRevocation(_ reason: AccountDeviceRevocationReason?, uid: String) {
        stopDeviceObservation()
        stopEntitlementObservation()
        deviceSessionCache?.removeSession(for: uid)
        try? auth.signOut()
        state = .guest
        deviceAccessState = .revoked(reason)
        errorMessage = reason?.message ?? "This Mac no longer has access to the Commit+ account."
        presentedSheet = nil
        scheduleSettingsSyncEligibilityUpdate()
    }

    private func finishLocalSignOut() {
        let uid = account?.uid ?? pendingTemporaryAccount?.uid
        do {
            try auth.signOut()
            if let uid { deviceSessionCache?.removeSession(for: uid) }
            stopDeviceObservation()
            stopEntitlementObservation()
            pendingTemporaryAccount = nil
            state = .guest
            deviceAccessState = deviceAccessProvider == nil ? .unavailable : .unverified
            presentedSheet = nil
            errorMessage = nil
            pendingLinkEmail = nil
            scheduleSettingsSyncEligibilityUpdate()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func stopDeviceObservation() {
        deviceObservation?.cancel()
        deviceObservation = nil
    }

    private static func currentDevice(from metadata: AccountDeviceMetadata) -> AccountDevice {
        AccountDevice(
            id: metadata.deviceID,
            modelFamily: metadata.modelFamily,
            osVersion: metadata.osVersion,
            appVersion: metadata.appVersion,
            status: .active,
            createdAt: .distantPast,
            lastSeenAt: .now,
            revokedAt: nil,
            revokedReason: nil
        )
    }

    private func startEntitlementObservation(for uid: String) {
        stopEntitlementObservation()
        if let cachedEntitlement = entitlementCache?.cachedEntitlement(for: uid) {
            entitlement = cachedEntitlement.entitlement
            entitlementLastUpdatedAt = cachedEntitlement.updatedAt
            isUsingCachedEntitlement = true
        }
        guard let entitlementProvider else { return }
        entitlementObservation = entitlementProvider.observe(
            uid: uid,
            onChange: { [weak self] entitlement in
                self?.applyEntitlement(entitlement, uid: uid)
            },
            onError: { [weak self] message in
                guard self?.account?.uid == uid else { return }
                self?.entitlementError = message
                self?.isUsingCachedEntitlement = self?.entitlementLastUpdatedAt != nil
                self?.scheduleSettingsSyncEligibilityUpdate()
            }
        )
    }

    private func applyEntitlement(_ entitlement: AccountEntitlement, uid: String) {
        guard account?.uid == uid else { return }
        self.entitlement = entitlement
        entitlementError = nil
        let updatedAt = Date.now
        entitlementLastUpdatedAt = updatedAt
        isUsingCachedEntitlement = false
        entitlementCache?.save(
            CachedAccountEntitlement(entitlement: entitlement, updatedAt: updatedAt),
            for: uid
        )
        scheduleSettingsSyncEligibilityUpdate()
    }

    private func stopEntitlementObservation() {
        entitlementObservation?.cancel()
        entitlementObservation = nil
        entitlement = .free
        entitlementError = nil
        entitlementLastUpdatedAt = nil
        isUsingCachedEntitlement = false
        scheduleSettingsSyncEligibilityUpdate()
    }

    func setSettingsSyncEnabled(_ enabled: Bool) {
        guard account != nil else { return }
        appState.syncEnabled = enabled
    }

    func resolveInitialSettingsChoice(_ choice: InitialSettingsChoice) async {
        await settingsSyncService?.resolveInitialChoice(choice)
    }

    func synchronizeSettingsNow() async {
        guard let settingsSyncService else {
            settingsSyncStatus = account == nil ? .off : .locked
            return
        }
        await settingsSyncService.updateEligibility(
            uid: account?.uid,
            enabled: appState.syncEnabled
        )
    }

    private func bindSettingsSync() {
        guard let settingsSyncService else { return }

        settingsSyncService.$status
            .sink { [weak self] status in
                guard let self else { return }
                settingsSyncStatus = status
                if case .needsInitialChoice = status {
                    presentSettingsConflictSheet()
                } else if presentedSheet == .settingsConflict {
                    presentedSheet = nil
                }
            }
            .store(in: &cancellables)

        appState.settingsSnapshotPublisher
            .dropFirst()
            .sink { [weak self] snapshot in
                guard let self else { return }
                settingsSyncService.localSettingsDidChange(snapshot)
            }
            .store(in: &cancellables)

        appState.$syncEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.scheduleSettingsSyncEligibilityUpdate(enabled: enabled)
            }
            .store(in: &cancellables)
    }

    private func scheduleSettingsSyncEligibilityUpdate(enabled enabledOverride: Bool? = nil) {
        settingsEligibilityTask?.cancel()
        guard let settingsSyncService else {
            settingsSyncStatus = account == nil ? .off : .locked
            return
        }
        let uid = account?.uid
        let enabled = enabledOverride ?? appState.syncEnabled
        settingsEligibilityTask = Task {
            guard !Task.isCancelled else { return }
            await settingsSyncService.updateEligibility(
                uid: uid,
                enabled: enabled
            )
        }
    }

    private func presentSettingsConflictSheet() {
        guard presentedSheet != .settingsConflict else { return }
        guard presentedSheet != nil else {
            presentSheet(.settingsConflict)
            return
        }

        let sourceWindow = sheetPresentationWindow
        presentedSheet = nil
        Task { @MainActor [weak self, weak sourceWindow] in
            guard let self else { return }
            guard case .needsInitialChoice = settingsSyncStatus else { return }
            presentSheet(.settingsConflict, in: sourceWindow)
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
