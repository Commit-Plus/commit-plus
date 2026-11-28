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
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import GoogleSignIn

@MainActor
final class FirebaseAuthService: AccountAuthenticating {
    private var pendingGoogleCredential: AuthCredential?

    var currentAccount: AccountSnapshot? {
        Auth.auth().currentUser.map(Self.snapshot)
    }

    func refreshCurrentAccount() async throws -> AccountSnapshot {
        guard let user = Auth.auth().currentUser else {
            throw AccountAuthError.message("Sign in before refreshing your profile.")
        }

        do {
            try await user.reload()
            guard let refreshedUser = Auth.auth().currentUser else {
                throw AccountAuthError.message("Your Commit+ session is no longer available.")
            }
            return Self.snapshot(refreshedUser)
        } catch let error as AccountAuthError {
            throw error
        } catch {
            throw map(error)
        }
    }

    func signIn(email: String, password: String) async throws -> AccountSnapshot {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return Self.snapshot(result.user)
        } catch {
            throw map(error)
        }
    }

    func createAccount(email: String, password: String) async throws -> AccountSnapshot {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            return Self.snapshot(result.user)
        } catch {
            throw map(error)
        }
    }

    func signIn(customToken: String) async throws -> AccountSnapshot {
        do {
            let result = try await Auth.auth().signIn(withCustomToken: customToken)
            pendingGoogleCredential = nil
            return Self.snapshot(result.user)
        } catch {
            throw map(error)
        }
    }

    func signInWithGoogle() async throws -> AccountSnapshot {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let window = NSApp.keyWindow ?? NSApp.windows.first else {
            throw AccountAuthError.googlePresentationUnavailable
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
        } catch {
            throw AccountAuthError.message(error.localizedDescription)
        }

        guard let idToken = result.user.idToken?.tokenString else {
            throw AccountAuthError.message("Google did not return an identity token.")
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            pendingGoogleCredential = nil
            return Self.snapshot(authResult.user)
        } catch {
            let nsError = error as NSError
            if AuthErrorCode(rawValue: nsError.code) == .accountExistsWithDifferentCredential {
                pendingGoogleCredential =
                    nsError.userInfo[AuthErrors.userInfoUpdatedCredentialKey] as? AuthCredential
                    ?? credential
            }
            throw map(error)
        }
    }

    func completePendingLink(email: String, password: String) async throws -> AccountSnapshot {
        guard let pendingGoogleCredential else {
            throw AccountAuthError.message("Start Google Sign-In again before linking your account.")
        }

        do {
            let signInResult = try await Auth.auth().signIn(withEmail: email, password: password)
            let linkResult = try await signInResult.user.link(with: pendingGoogleCredential)
            self.pendingGoogleCredential = nil
            return Self.snapshot(linkResult.user)
        } catch {
            throw map(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw map(error)
        }
    }

    func deleteAccount() async throws {
        do {
            _ = try await Functions.functions(region: "asia-southeast1").httpsCallable("deleteAccount").call()
            try? Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            pendingGoogleCredential = nil
        } catch {
            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain,
               FunctionsErrorCode(rawValue: nsError.code) == .failedPrecondition {
                throw AccountAuthError.requiresRecentAuthentication
            }
            throw map(error)
        }
    }

    func signOut() throws {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            pendingGoogleCredential = nil
        } catch {
            throw map(error)
        }
    }

    private static func snapshot(_ user: User) -> AccountSnapshot {
        AccountSnapshot(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
            providerIDs: user.providerData.map(\.providerID).sorted()
        )
    }

    private func map(_ error: Error) -> AccountAuthError {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return .message(error.localizedDescription)
        }

        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound:
            return .invalidCredentials
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .weakPassword:
            return .weakPassword
        case .networkError:
            return .networkUnavailable
        case .accountExistsWithDifferentCredential:
            let email = nsError.userInfo[AuthErrors.userInfoEmailKey] as? String ?? ""
            return .needsExistingMethod(email: email, providerIDs: [EmailAuthProviderID])
        default:
            return .message(error.localizedDescription)
        }
    }
}
