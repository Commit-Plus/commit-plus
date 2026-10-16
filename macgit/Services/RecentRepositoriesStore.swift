//
//  RecentRepositoriesStore.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
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
import Combine

struct RecentRepository: Codable, Identifiable, Equatable {
    let id: UUID
    var url: URL
    var lastOpened: Date
    var name: String

    init(url: URL, lastOpened: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.url = url
        self.lastOpened = lastOpened
        self.name = url.lastPathComponent
    }
}

@MainActor
final class RecentRepositoriesStore: ObservableObject {
    static let shared = RecentRepositoriesStore()
    private var observation: AnyCancellable?

    @Published var repositories: [RecentRepository] = []

    private init() {
        observation = RepositoryCatalogStore.shared.$snapshot.sink { [weak self] state in
            let recents = state.repositories.filter { $0.lastOpened != nil }
                .sorted { $0.lastOpened! > $1.lastOpened! }.prefix(20)
                .map { record in
                    var recent = RecentRepository(url: URL(fileURLWithPath: record.path), lastOpened: record.lastOpened!, id: record.id)
                    recent.name = record.name
                    return recent
                }
            if self?.repositories.map(\.id) != recents.map(\.id)
                || self?.repositories.map(\.lastOpened) != recents.map(\.lastOpened) {
                self?.repositories = recents
            }
        }
    }

    func add(_ url: URL) {
        RepositoryCatalogStore.shared.open(url)
    }

    func remove(at offsets: IndexSet) {
        RepositoryCatalogStore.shared.removeRecent(Set(offsets.compactMap { repositories.indices.contains($0) ? repositories[$0].url.path : nil }))
    }

    func remove(_ repo: RecentRepository) {
        RepositoryCatalogStore.shared.removeRecent([RepositoryCatalogSnapshot.path(repo.url)])
    }

    func removeAll() {
        RepositoryCatalogStore.shared.removeRecent(Set(repositories.map { RepositoryCatalogSnapshot.path($0.url) }))
    }
}
