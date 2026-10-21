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

@MainActor
protocol GitProviderAccountStore {
    var accountOwnerID: String { get }

    func accounts() async throws -> [GitProviderAccount]
    func updateCloudAccount(uid: String?) async throws
    func save(_ account: GitProviderAccount) async throws
    func delete(accountID: String) async throws
    /// Retries cloud writes that failed earlier, without the full reconciliation.
    func uploadPendingChanges() async
}

extension GitProviderAccountStore {
    func uploadPendingChanges() async {}
}

@MainActor
protocol GitProviderAccountCloudStore {
    func accounts(forMacgitUID uid: String) async throws -> [GitProviderAccount]
    func save(_ account: GitProviderAccount) async throws
    func delete(accountID: String, macgitUID: String) async throws
}
