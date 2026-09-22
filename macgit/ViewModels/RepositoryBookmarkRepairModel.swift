// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

@MainActor
final class RepositoryBookmarkRepairModel: ObservableObject {
    let bookmark: RepositoryBookmark
    @Published private(set) var repositoryURL: URL?
    @Published private(set) var remotes: [RepositoryBookmarkRemote] = []
    @Published var selectedRemoteID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    private var loadID = UUID()

    init(bookmark: RepositoryBookmark) {
        self.bookmark = bookmark
    }

    var selectedRemote: RepositoryBookmarkRemote? {
        remotes.first { $0.id == selectedRemoteID }
    }

    var canSave: Bool {
        repositoryURL != nil && selectedRemote != nil && !isLoading && !isSaving
    }

    func selectRepository(_ url: URL) async {
        let requestID = UUID()
        loadID = requestID
        repositoryURL = url
        remotes = []
        selectedRemoteID = nil
        errorMessage = nil
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else {
            errorMessage = "Choose a Git repository folder containing a .git directory or file."
            return
        }
        do {
            let loaded = try await GitStatusService.shared.repositoryBookmarkRemotes(in: url)
            guard loadID == requestID, !Task.isCancelled else { return }
            remotes = loaded
            selectedRemoteID = loaded.first(where: { $0.identity.canonicalKey == bookmark.canonicalKey })?.id
                ?? loaded.first?.id
            if loaded.isEmpty {
                errorMessage = "This folder has no supported remote URL. Choose another repository, or add a remote before updating the bookmark."
            }
        } catch {
            guard loadID == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func save(using controller: RepositoryBookmarkController) async -> Bool {
        guard canSave, let repositoryURL, let selectedRemote else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await controller.updateBookmark(bookmark, from: repositoryURL, remote: selectedRemote)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
