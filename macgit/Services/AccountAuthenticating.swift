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

import Foundation

enum AccountAuthError: LocalizedError, Equatable {
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case networkUnavailable
    case needsExistingMethod(email: String, providerIDs: [String])
    case googlePresentationUnavailable
    case requiresRecentAuthentication
    case cloudNotConfigured
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "The email or password is incorrect."
        case .emailAlreadyInUse:
            return "An account already exists for this email."
        case .weakPassword:
            return "Use a password with at least 6 characters."
        case .networkUnavailable:
            return "Connect to the internet and try again."
        case .needsExistingMethod:
            return "Sign in using the existing method to link this account."
        case .googlePresentationUnavailable:
            return "Commit+ could not present Google Sign-In."
        case .requiresRecentAuthentication:
            return "For security, sign in again before deleting your account."
        case .cloudNotConfigured:
            return "Cloud accounts are not configured in this build."
        case .message(let text):
            return text
        }
    }
}

protocol AccountAuthenticating {
    var currentAccount: AccountSnapshot? { get }

    func refreshCurrentAccount() async throws -> AccountSnapshot
    func signIn(email: String, password: String) async throws -> AccountSnapshot
    func createAccount(email: String, password: String) async throws -> AccountSnapshot
    func signIn(customToken: String) async throws -> AccountSnapshot
    func signInWithGoogle() async throws -> AccountSnapshot
    func completePendingLink(email: String, password: String) async throws -> AccountSnapshot
    func sendPasswordReset(email: String) async throws
    func deleteAccount() async throws
    func signOut() throws
}

extension AccountAuthenticating {
    func signIn(customToken: String) async throws -> AccountSnapshot {
        throw AccountAuthError.cloudNotConfigured
    }

    func refreshCurrentAccount() async throws -> AccountSnapshot {
        guard let currentAccount else {
            throw AccountAuthError.message("Sign in before refreshing your profile.")
        }
        return currentAccount
    }

}

enum AccountSessionState: Equatable {
    case guest
    case loading
    case authenticated(AccountSnapshot)
    case failed(String)
}

enum AuthenticationMode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case createAccount = "Create Account"

    var id: Self { self }
}

enum AccountSheet: Identifiable, Equatable {
    case authentication(AuthenticationMode)
    case settingsConflict
    case deviceLimit

    var id: String {
        switch self {
        case .authentication(let mode):
            return "authentication-\(mode.rawValue)"
        case .settingsConflict:
            return "settings-conflict"
        case .deviceLimit:
            return "device-limit"
        }
    }
}
