//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

extension MainWindowView {
    func handleSearchAction(_ action: SearchAction) {
        switch action {
        case .showCommit(let hash):
            selectedItem = .item(.history)
            selectedBranchName = hash
        case .showFile(let path):
            prepareToOpenSearchFile(path)
        case .checkoutBranch(let branch):
            if branch.hasPrefix("remotes/") {
                let localName = branch.replacingOccurrences(of: "remotes/", with: "")
                if let slashIndex = localName.firstIndex(of: "/") {
                    let branchName = String(localName[localName.index(after: slashIndex)...])
                    branchToCheckout = branchName
                    showingCheckoutConfirmation = true
                }
            } else {
                branchToCheckout = branch
                showingCheckoutConfirmation = true
            }
        case .showTag(let tag):
            tagToCheckout = tag
            showingDetachedHeadConfirmation = true
        }
    }

    func prepareToOpenSearchFile(_ relativePath: String, lineTarget: SearchFileLineTarget? = nil) {
        let applications = SearchFileApplicationResolver.availableApplications()

        if let preferredBundleIdentifier = appState.preferredSearchFileApplicationBundleIdentifier {
            if let preferredApplication = applications.first(where: {
                $0.bundleIdentifier == preferredBundleIdentifier
            }) {
                openSearchFile(relativePath, lineTarget: lineTarget, using: preferredApplication)
                return
            }

            appState.preferredSearchFileApplicationBundleIdentifier = nil
        }

        guard !applications.isEmpty else {
            syncState.showError("No supported application is available to open this file.")
            return
        }

        pendingSearchFileOpenRequest = SearchFileOpenRequest(
            relativePath: relativePath,
            lineTarget: lineTarget,
            applications: applications
        )
    }

    func openSearchFile(
        _ relativePath: String,
        lineTarget: SearchFileLineTarget? = nil,
        using application: SearchFileApplication
    ) {
        let progressID = operationProgress.begin(
            message: "Opening \((relativePath as NSString).lastPathComponent) in \(application.displayName)...",
            canCancel: false
        )

        // A newer open request replaces one that is still resolving its line.
        searchFileOpenTask?.cancel()
        searchFileOpenTask = Task {
            defer { operationProgress.end(progressID) }
            do {
                try await SearchFileOpener.open(
                    relativePath: relativePath,
                    lineTarget: lineTarget,
                    in: repositoryURL,
                    using: application
                )
            } catch is CancellationError {
            } catch {
                syncState.showError(error.localizedDescription)
            }
        }
    }
}
