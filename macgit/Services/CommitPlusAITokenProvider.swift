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
import FirebaseAuth
import FirebaseCore

nonisolated struct CommitPlusAISession: Equatable, Sendable {
    let uid: String
    let generation: String
}

protocol CommitPlusAITokenProviding: Sendable {
    @MainActor func currentSession() -> CommitPlusAISession?
    @MainActor func token(for session: CommitPlusAISession, forceRefresh: Bool) async throws -> String
}

@MainActor
final class FirebaseCommitPlusAITokenProvider: CommitPlusAITokenProviding {
    private var observedUser: User?
    private var generation = UUID().uuidString

    func currentSession() -> CommitPlusAISession? {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else {
            observedUser = nil
            generation = UUID().uuidString
            return nil
        }
        if observedUser !== user {
            observedUser = user
            generation = UUID().uuidString
        }
        return CommitPlusAISession(uid: user.uid, generation: generation)
    }
    func token(for session: CommitPlusAISession, forceRefresh: Bool) async throws -> String {
        guard currentSession() == session, let user = Auth.auth().currentUser else { throw CommitPlusAIError.sessionChanged }
        let token = try await user.getIDToken(forcingRefresh: forceRefresh)
        guard currentSession() == session else { throw CommitPlusAIError.sessionChanged }
        return token
    }
}
