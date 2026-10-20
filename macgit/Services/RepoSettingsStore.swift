//
//  RepoSettingsStore.swift
//  macgit
//

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
final class RepoSettingsStore {
    static let shared = RepoSettingsStore()
    let dataStore: LocalDataStore

    init(dataStore: LocalDataStore? = nil) { self.dataStore = dataStore ?? .shared }

    /// When no usable default remote is saved (settings can be created by flows that do not know
    /// the remotes), a linked worktree inherits the main worktree's default remote.
    func settings(for repositoryPath: String, mainWorktreePath: String? = nil,
                  currentBranch: String?, remotes: [String]) async -> RepoSettings {
        var settings = (try? await dataStore.readValue(RepoSettings.self, in: "repoSettings", id: repositoryPath))
            ?? RepoSettings.defaults(currentBranch: currentBranch, remotes: [])
        guard !remotes.isEmpty, !(settings.defaultRemoteName.map(remotes.contains) ?? false) else { return settings }
        if let mainWorktreePath, mainWorktreePath != repositoryPath,
           let mainSettings = try? await dataStore.readValue(RepoSettings.self, in: "repoSettings", id: mainWorktreePath),
           let remote = mainSettings.defaultRemoteName, remotes.contains(remote) {
            settings.defaultRemoteName = remote
        } else {
            settings.defaultRemoteName = RepoSettings.preferredRemote(in: remotes)
        }
        return settings
    }

    func update(for repositoryPath: String, settings: RepoSettings, pendingCommitRuleUID: String? = nil) async throws {
        try await dataStore.transaction { transaction in
            try transaction.set(settings, in: "repoSettings", id: repositoryPath)
            if let uid = pendingCommitRuleUID {
                try transaction.set(settings.skipProtectedBranchCommitWarnings,
                                    in: "commitRulePending", id: "\(uid)|\(repositoryPath)")
            }
        }
    }
}
