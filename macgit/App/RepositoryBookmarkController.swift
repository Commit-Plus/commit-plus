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

import Combine
import Foundation

enum RepositoryBookmarkError: LocalizedError {
    case noRemote
    case unsupportedRemote
    case folderDoesNotMatch
    case bookmarkChanged
    case remoteChanged

    var errorDescription: String? {
        switch self {
        case .noRemote:
            "This repository has no Git remote to bookmark."
        case .unsupportedRemote:
            "The repository remote URL could not be recognized."
        case .folderDoesNotMatch:
            "None of this folder's remotes match the bookmark. If the repository was renamed or moved, update the bookmark from this folder."
        case .bookmarkChanged:
            "This bookmark changed or was removed. Close this window and try again."
        case .remoteChanged:
            "The selected remote changed. Choose the folder again to review its current URL."
        }
    }
}

@MainActor
final class RepositoryBookmarkController: ObservableObject {
    @Published private(set) var bookmarks: [RepositoryBookmark] = []
    @Published private(set) var localPaths: [String: String] = [:]
    @Published private(set) var syncingBookmarkIDs: Set<String> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var mismatchedBookmarkIDs: Set<String> = []
    @Published private(set) var hasPendingChanges = false
    @Published private(set) var isRetryingSync = false

    private let cloudStore: RepositoryBookmarkCloudStore?
    private let dataStore: LocalDataStore
    @Published private var activeUID: String?
    private var observation: ObservationToken?

    init(cloudStore: RepositoryBookmarkCloudStore?, dataStore: LocalDataStore? = nil) {
        self.cloudStore = cloudStore
        self.dataStore = dataStore ?? .shared
    }

    deinit { observation?.cancel() }

    func load() throws {
        bookmarks = try dataStore.values(RepositoryBookmark.self, in: "bookmarks").values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        localPaths = try dataStore.values(String.self, in: "bookmarkPaths")
        mismatchedBookmarkIDs.formIntersection(Set(bookmarks.map(\.id)))
        let uploads = try dataStore.values(String.self, in: "bookmarkUploads")
        let deletes = try dataStore.values(String.self, in: "bookmarkDeletes")
        hasPendingChanges = !uploads.isEmpty || !deletes.isEmpty
    }

    var canSyncPendingChanges: Bool { activeUID != nil && cloudStore != nil }

    func retryPendingChanges() async {
        guard hasPendingChanges, !isRetryingSync, let uid = activeUID, let cloudStore else { return }
        isRetryingSync = true
        defer { isRetryingSync = false }
        await flushPendingChanges(uid: uid, cloudStore: cloudStore)
        do { try load() } catch { errorMessage = error.localizedDescription }
    }

    func updateAccount(_ account: AccountSnapshot?) async {
        do {
            try await dataStore.prepare()
            try load()
            let uid = account?.uid
            guard uid != activeUID else { return }
            observation?.cancel()
            observation = nil
            activeUID = uid
            guard let uid, let cloudStore else { return }
            await flushPendingChanges(uid: uid, cloudStore: cloudStore)
            guard activeUID == uid else { return }
            let cloudBookmarks = try await cloudStore.bookmarks(uid: uid)
            guard activeUID == uid else { return }
            try await applyCloudBookmarks(cloudBookmarks, uid: uid)
            guard activeUID == uid else { return }
            observation = cloudStore.observe(uid: uid) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.activeUID == uid else { return }
                    do {
                        try await self.applyCloudBookmarks(result.get(), uid: uid)
                    } catch { self.errorMessage = error.localizedDescription }
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func bookmark(forID id: String) -> RepositoryBookmark? { bookmarks.first { $0.id == id } }

    func bookmark(remoteURLString: String) -> RepositoryBookmark? {
        guard let identity = RepositoryBookmarkIdentity.resolve(remoteURLString: remoteURLString) else { return nil }
        return bookmarks.first { $0.canonicalKey == identity.canonicalKey }
    }

    func localURL(for bookmark: RepositoryBookmark) -> URL? {
        localPaths[bookmark.id].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func bookmarkID(linkedTo url: URL) -> String? { localPaths.first { $0.value == url.path }?.key }

    func bookmarksNeedingAttention(at url: URL) -> [RepositoryBookmark] {
        bookmarks.filter { localPaths[$0.id] == url.path && mismatchedBookmarkIDs.contains($0.id) }
    }

    /// Replace URL-derived identities in one local transaction, retaining upload and
    /// deletion markers so an offline repair survives a restart and stale cloud data.
    func updateBookmark(
        _ bookmark: RepositoryBookmark,
        from repositoryURL: URL,
        remote: RepositoryBookmarkRemote
    ) async throws -> RepositoryBookmark {
        let currentRemotes = try await GitStatusService.shared.repositoryBookmarkRemotes(in: repositoryURL)
        guard currentRemotes.contains(remote) else { throw RepositoryBookmarkError.remoteChanged }
        let result = try await dataStore.transaction { transaction in
            guard let current = try transaction.value(RepositoryBookmark.self, in: "bookmarks", id: bookmark.id),
                  current.canonicalKey == bookmark.canonicalKey else { throw RepositoryBookmarkError.bookmarkChanged }
            let identity = remote.identity
            let existing = try transaction.values(RepositoryBookmark.self, in: "bookmarks").values.first {
                $0.id != current.id && $0.canonicalKey == identity.canonicalKey
            }
            let updated = RepositoryBookmark(
                id: existing?.id ?? identity.documentID,
                canonicalKey: identity.canonicalKey,
                name: identity.repositoryName,
                provider: identity.provider,
                host: identity.host,
                ownerPath: identity.ownerPath,
                remoteURL: identity.canonicalRemoteURL,
                createdAt: existing?.createdAt ?? current.createdAt,
                updatedAt: Date()
            )
            if updated.id != current.id {
                transaction.remove(in: "bookmarks", id: current.id)
                transaction.remove(in: "bookmarkPaths", id: current.id)
                transaction.remove(in: "bookmarkUploads", id: current.id)
                try transaction.set(UUID().uuidString, in: "bookmarkDeletes", id: current.id)
            }
            try transaction.set(updated, in: "bookmarks", id: updated.id)
            try transaction.set(repositoryURL.path, in: "bookmarkPaths", id: updated.id)
            transaction.remove(in: "bookmarkDeletes", id: updated.id)
            try transaction.set(UUID().uuidString, in: "bookmarkUploads", id: updated.id)
            return updated
        }
        mismatchedBookmarkIDs.remove(bookmark.id)
        mismatchedBookmarkIDs.remove(result.id)
        try load()
        if let uid = activeUID, let cloudStore {
            await upload(result, uid: uid, cloudStore: cloudStore)
            // Keep the cloud's old bookmark until its replacement has been saved.
            if result.id != bookmark.id,
               try dataStore.value(String.self, in: "bookmarkUploads", id: result.id) == nil {
                await deleteFromCloud(bookmark.id, uid: uid, cloudStore: cloudStore)
            }
        }
        return result
    }

    func addBookmark(for repositoryURL: URL) async throws -> RepositoryBookmark {
        let remoteURLString = try await bookmarkRemoteURL(in: repositoryURL)
        guard let identity = RepositoryBookmarkIdentity.resolve(remoteURLString: remoteURLString) else {
            throw RepositoryBookmarkError.unsupportedRemote
        }
        let bookmark = try await dataStore.transaction { transaction in
            let existing = try transaction.values(RepositoryBookmark.self, in: "bookmarks").values.first { $0.canonicalKey == identity.canonicalKey }
            let bookmark = existing ?? RepositoryBookmark(identity: identity)
            try transaction.set(bookmark, in: "bookmarks", id: bookmark.id)
            try transaction.set(repositoryURL.path, in: "bookmarkPaths", id: bookmark.id)
            if existing == nil {
                transaction.remove(in: "bookmarkDeletes", id: bookmark.id)
                try transaction.set(UUID().uuidString, in: "bookmarkUploads", id: bookmark.id)
            }
            return bookmark
        }
        try load()
        if let uid = activeUID, let cloudStore { await upload(bookmark, uid: uid, cloudStore: cloudStore) }
        return bookmark
    }

    func removeBookmark(_ bookmark: RepositoryBookmark) async {
        do {
            try await dataStore.transaction { transaction in
                transaction.remove(in: "bookmarks", id: bookmark.id)
                transaction.remove(in: "bookmarkPaths", id: bookmark.id)
                transaction.remove(in: "bookmarkUploads", id: bookmark.id)
                try transaction.set(UUID().uuidString, in: "bookmarkDeletes", id: bookmark.id)
            }
            try load()
            if let uid = activeUID, let cloudStore { await deleteFromCloud(bookmark.id, uid: uid, cloudStore: cloudStore) }
        } catch { errorMessage = error.localizedDescription }
    }

    func link(_ bookmark: RepositoryBookmark, to repositoryURL: URL) async throws {
        try await dataStore.transaction { transaction in
            try transaction.set(repositoryURL.path, in: "bookmarkPaths", id: bookmark.id)
        }
        try load()
    }

    func validateAndLink(_ bookmark: RepositoryBookmark, to repositoryURL: URL) async throws {
        let remoteURLs = await GitStatusService.shared.remoteURLs(in: repositoryURL)
        guard !remoteURLs.isEmpty else { throw RepositoryBookmarkError.noRemote }
        guard remoteURLs.contains(where: {
            RepositoryBookmarkIdentity.resolve(remoteURLString: $0)?.canonicalKey == bookmark.canonicalKey
        }) else { throw RepositoryBookmarkError.folderDoesNotMatch }
        try await link(bookmark, to: repositoryURL)
    }

    func linkMatchingBookmarks(to repositoryURLs: [URL]) async {
        var visited: Set<URL> = []
        for repositoryURL in repositoryURLs where visited.insert(repositoryURL).inserted {
            guard !Task.isCancelled else { return }
            guard FileManager.default.fileExists(atPath: repositoryURL.appendingPathComponent(".git").path) else {
                continue
            }
            // A Git read failure is not evidence of a renamed repository.
            guard let remotes = try? await GitStatusService.shared.repositoryBookmarkRemotes(in: repositoryURL) else { continue }
            let keys = Set(remotes.map(\.identity.canonicalKey))
            guard !Task.isCancelled else { return }
            for bookmark in bookmarks where localPaths[bookmark.id] == repositoryURL.path {
                if keys.contains(bookmark.canonicalKey) {
                    mismatchedBookmarkIDs.remove(bookmark.id)
                } else {
                    mismatchedBookmarkIDs.insert(bookmark.id)
                }
            }
            let matches = bookmarks.filter { localPaths[$0.id] == nil && keys.contains($0.canonicalKey) }
            guard !matches.isEmpty else { continue }
            do {
                try await dataStore.transaction { transaction in
                    for bookmark in matches {
                        // Recheck persisted state: a cloud update or manual link may have won the race.
                        guard let current = try transaction.value(RepositoryBookmark.self, in: "bookmarks", id: bookmark.id),
                              keys.contains(current.canonicalKey),
                              try transaction.value(String.self, in: "bookmarkPaths", id: bookmark.id) == nil else { continue }
                        try transaction.set(repositoryURL.path, in: "bookmarkPaths", id: bookmark.id)
                    }
                }
                try load()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func unlinkLocalFolder(for bookmark: RepositoryBookmark) async {
        do {
            try await dataStore.transaction { $0.remove(in: "bookmarkPaths", id: bookmark.id) }
            try load()
        } catch { errorMessage = error.localizedDescription }
    }

    func clearError() { errorMessage = nil }

    private func bookmarkRemoteURL(in repositoryURL: URL) async throws -> String {
        let origin = await GitStatusService.shared.remoteURL(remote: "origin", in: repositoryURL)
        if !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return origin }
        for remote in await GitStatusService.shared.remotes(in: repositoryURL) {
            let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
            if !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return remoteURL }
        }
        throw RepositoryBookmarkError.noRemote
    }

    private func acknowledge(_ collection: String, id: String, version: String, uid: String) async throws {
        try await dataStore.transaction { transaction in
            guard self.activeUID == uid,
                  try transaction.value(String.self, in: collection, id: id) == version else { return }
            transaction.remove(in: collection, id: id)
        }
        try load()
    }

    private func upload(_ bookmark: RepositoryBookmark, uid: String, cloudStore: RepositoryBookmarkCloudStore) async {
        guard activeUID == uid else { return }
        syncingBookmarkIDs.insert(bookmark.id)
        defer { syncingBookmarkIDs.remove(bookmark.id) }
        do {
            guard let version = try dataStore.value(String.self, in: "bookmarkUploads", id: bookmark.id) else { return }
            try await cloudStore.save(bookmark, uid: uid)
            try await acknowledge("bookmarkUploads", id: bookmark.id, version: version, uid: uid)
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteFromCloud(_ id: String, uid: String, cloudStore: RepositoryBookmarkCloudStore) async {
        guard activeUID == uid else { return }
        syncingBookmarkIDs.insert(id)
        defer { syncingBookmarkIDs.remove(id) }
        do {
            guard let version = try dataStore.value(String.self, in: "bookmarkDeletes", id: id) else { return }
            try await cloudStore.delete(bookmarkID: id, uid: uid)
            try await acknowledge("bookmarkDeletes", id: id, version: version, uid: uid)
        } catch { errorMessage = error.localizedDescription }
    }

    private func flushPendingChanges(uid: String, cloudStore: RepositoryBookmarkCloudStore) async {
        do {
            for bookmark in bookmarks {
                guard activeUID == uid else { return }
                if syncingBookmarkIDs.contains(bookmark.id) { continue }
                await upload(bookmark, uid: uid, cloudStore: cloudStore)
            }
            // A replacement must reach the cloud before deleting its old identity.
            guard try dataStore.values(String.self, in: "bookmarkUploads").isEmpty else { return }
            for id in try dataStore.values(String.self, in: "bookmarkDeletes").keys {
                guard activeUID == uid else { return }
                if syncingBookmarkIDs.contains(id) { continue }
                await deleteFromCloud(id, uid: uid, cloudStore: cloudStore)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func applyCloudBookmarks(_ cloudBookmarks: [RepositoryBookmark], uid: String) async throws {
        try await dataStore.transaction { transaction in
            guard self.activeUID == uid else { return }
            let pendingUploads = try transaction.values(String.self, in: "bookmarkUploads")
            let pendingDeletes = try transaction.values(String.self, in: "bookmarkDeletes")
            var merged = Dictionary(cloudBookmarks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for (id, bookmark) in try transaction.values(RepositoryBookmark.self, in: "bookmarks") where pendingUploads[id] != nil {
                merged[id] = bookmark
            }
            for id in pendingDeletes.keys { merged[id] = nil }
            for id in try transaction.values(RepositoryBookmark.self, in: "bookmarks").keys where merged[id] == nil {
                transaction.remove(in: "bookmarks", id: id)
            }
            for (id, bookmark) in merged { try transaction.set(bookmark, in: "bookmarks", id: id) }
            for id in try transaction.values(String.self, in: "bookmarkPaths").keys where merged[id] == nil {
                transaction.remove(in: "bookmarkPaths", id: id)
            }
        }
        try load()
    }
}
