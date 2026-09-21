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

    var errorDescription: String? {
        switch self {
        case .noRemote:
            "This repository has no Git remote to bookmark."
        case .unsupportedRemote:
            "The repository remote URL could not be recognized."
        case .folderDoesNotMatch:
            "The selected folder belongs to a different repository."
        }
    }
}

@MainActor
final class RepositoryBookmarkController: ObservableObject {
    @Published private(set) var bookmarks: [RepositoryBookmark] = []
    @Published private(set) var localPaths: [String: String] = [:]
    @Published private(set) var syncingBookmarkIDs: Set<String> = []
    @Published private(set) var errorMessage: String?

    private let cloudStore: RepositoryBookmarkCloudStore?
    private let dataStore: LocalDataStore
    private var activeUID: String?
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
        let remoteURLString = try await bookmarkRemoteURL(in: repositoryURL)
        guard let identity = RepositoryBookmarkIdentity.resolve(remoteURLString: remoteURLString),
              identity.canonicalKey == bookmark.canonicalKey else { throw RepositoryBookmarkError.folderDoesNotMatch }
        try await link(bookmark, to: repositoryURL)
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
            for id in try dataStore.values(String.self, in: "bookmarkDeletes").keys {
                await deleteFromCloud(id, uid: uid, cloudStore: cloudStore)
            }
            for bookmark in bookmarks { await upload(bookmark, uid: uid, cloudStore: cloudStore) }
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
