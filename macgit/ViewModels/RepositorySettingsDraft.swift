//
//  RepositorySettingsDraft.swift
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

enum SelectedBranchMode: String, Equatable {
    case detected
    case manual
}

struct RepositorySettingsDraft: Equatable {
    var selectedRemoteName: String
    var selectedBranchMode: SelectedBranchMode
    var selectedDetectedBranch: String
    var manualBranchName: String
    var pullStrategy: PullStrategy
    var autoFetchOverride: Bool?
    var refreshOnAppActiveOverride: Bool?
    var confirmDetachedHeadCheckout: Bool
    var confirmDestructiveStashActions: Bool
    var skipProtectedBranchCommitWarnings: Bool
    var useGlobalUserSettings: Bool
    var userName: String
    var userEmail: String
    let remotes: [String]
    let branches: [String]

    init(
        settings: RepoSettings,
        remotes: [String],
        branches: [String],
        currentBranch: String?
    ) {
        self.remotes = remotes
        self.branches = branches

        selectedRemoteName = Self.resolveRemote(
            savedRemoteName: settings.defaultRemoteName,
            remotes: remotes
        )

        if branches.contains(settings.defaultPullBranch) {
            selectedBranchMode = .detected
            selectedDetectedBranch = settings.defaultPullBranch
            manualBranchName = ""
        } else {
            selectedBranchMode = .manual
            selectedDetectedBranch = Self.resolveDetectedBranch(
                currentBranch: currentBranch,
                branches: branches
            )
            manualBranchName = settings.defaultPullBranch
        }

        pullStrategy = settings.pullStrategy
        autoFetchOverride = settings.autoFetchOverride
        refreshOnAppActiveOverride = settings.refreshOnAppActiveOverride
        confirmDetachedHeadCheckout = settings.confirmDetachedHeadCheckout
        confirmDestructiveStashActions = settings.confirmDestructiveStashActions
        skipProtectedBranchCommitWarnings = settings.skipProtectedBranchCommitWarnings
        useGlobalUserSettings = settings.useGlobalUserSettings
        userName = settings.userName
        userEmail = settings.userEmail
    }

    var resolvedSettings: RepoSettings {
        RepoSettings(
            defaultRemoteName: selectedRemoteName.isEmpty ? nil : selectedRemoteName,
            defaultPullBranch: resolvedPullBranch(),
            pullStrategy: pullStrategy,
            autoFetchOverride: autoFetchOverride,
            refreshOnAppActiveOverride: refreshOnAppActiveOverride,
            confirmDetachedHeadCheckout: confirmDetachedHeadCheckout,
            confirmDestructiveStashActions: confirmDestructiveStashActions,
            skipProtectedBranchCommitWarnings: skipProtectedBranchCommitWarnings,
            useGlobalUserSettings: useGlobalUserSettings,
            userName: userName,
            userEmail: userEmail
        )
    }

    private func resolvedPullBranch() -> String {
        switch selectedBranchMode {
        case .detected:
            return selectedDetectedBranch
        case .manual:
            return manualBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func resolveRemote(savedRemoteName: String?, remotes: [String]) -> String {
        if let savedRemoteName {
            return savedRemoteName
        }
        return remotes.first ?? ""
    }

    private static func resolveDetectedBranch(currentBranch: String?, branches: [String]) -> String {
        if let currentBranch, branches.contains(currentBranch) {
            return currentBranch
        }
        return branches.first ?? ""
    }
}
