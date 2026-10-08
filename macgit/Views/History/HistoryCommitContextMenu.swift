// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct HistoryCommitContextMenu: View {
    @EnvironmentObject private var customActionStore: CustomActionStore

    let contextCommits: [Commit]
    let primaryCommit: Commit?
    let headHash: String?
    let repositoryURL: URL
    let controller: HistoryCommitActionController

    private var singleCommit: Commit? {
        contextCommits.count == 1 ? contextCommits.first : nil
    }

    private var canCherryPick: Bool {
        !contextCommits.isEmpty && contextCommits.allSatisfy { !$0.isMerge }
    }

    private var canSquash: Bool {
        HistoryLoadPolicy.canSquashCommits(
            contextCommits,
            selectedHashes: contextCommits.map(\.hash),
            headHash: headHash
        )
    }

    var body: some View {
        Group {
            Button("Show Repository at Revision", systemImage: "folder") {
                if let singleCommit { controller.requestBrowseRevision(singleCommit) }
            }
            .disabled(singleCommit == nil)

            Button("Checkout Commit", systemImage: "arrow.right.to.line") {
                if let singleCommit { controller.requestCheckout(singleCommit) }
            }
            .disabled(singleCommit == nil)

            Button(
                contextCommits.count > 1 ? "Cherry Pick \(contextCommits.count) Commits" : "Cherry Pick",
                systemImage: "arrow.down.doc"
            ) {
                controller.requestCherryPick(contextCommits)
            }
            .disabled(!canCherryPick)

            Button("AI Explain This Commit", systemImage: "sparkles") {
                if let primaryCommit { controller.requestExplain(primaryCommit) }
            }
            .disabled(primaryCommit == nil)

            Divider()

            Button("Merge...", systemImage: "arrow.triangle.merge") {
                if let singleCommit { controller.requestMerge(singleCommit) }
            }
            .disabled(singleCommit == nil)

            Button("Rebase...", systemImage: "arrow.triangle.swap") {
                if let singleCommit { controller.requestRebase(singleCommit) }
            }
            .disabled(singleCommit == nil)

            Divider()

            Button("Squash Commits", systemImage: "rectangle.compress.vertical") {
                controller.requestSquash(contextCommits)
            }
            .disabled(!canSquash)

            Divider()

            Button("Tag...", systemImage: "tag") {
                if let singleCommit { controller.requestTag(singleCommit) }
            }
            .disabled(singleCommit == nil)

            Button("Branch...", systemImage: "arrow.triangle.branch") {
                if let singleCommit { controller.requestBranch(singleCommit) }
            }
            .disabled(singleCommit == nil)

            Divider()

            Button("Reset to this commit", systemImage: "arrow.counterclockwise") {
                if let singleCommit { controller.requestReset(singleCommit) }
            }
            .disabled(singleCommit == nil)

            Button("Reverse commit...", systemImage: "arrow.uturn.backward") {
                if let singleCommit { controller.requestRevert(singleCommit) }
            }
            .disabled(singleCommit == nil)

            Divider()

            Menu("Custom Actions") {
                let hashes = contextCommits.map(\.hash)
                CustomActionMenuContent(
                    store: customActionStore,
                    surface: .selectedCommits,
                    context: CustomActionInvocationContext(
                        repositoryURL: repositoryURL,
                        filePaths: [],
                        commitHashes: hashes
                    ),
                    onRun: { id, _ in controller.dependencies.runCustomAction(id, hashes) }
                )
            }

            Divider()

            Button(contextCommits.count > 1 ? "Copy Hashes" : "Copy Hash", systemImage: "doc.on.doc") {
                copy(contextCommits.map(\.hash).joined(separator: "\n"))
            }
            .disabled(contextCommits.isEmpty)

            Button(contextCommits.count > 1 ? "Copy Messages" : "Copy Message", systemImage: "doc.on.doc") {
                copy(contextCommits.map(\.message).joined(separator: "\n"))
            }
            .disabled(contextCommits.isEmpty)
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
