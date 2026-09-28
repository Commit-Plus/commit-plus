//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
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

actor BranchListCache {
    static let ttl: TimeInterval = 120
    static let defaultCapacity = 32

    enum Key: Hashable {
        case local(URL)
        case remote(URL, String)

        var repositoryURL: URL {
            switch self {
            case .local(let repositoryURL), .remote(let repositoryURL, _):
                return repositoryURL
            }
        }
    }

    private struct Entry {
        let values: [String]
        let createdAt: Date
    }

    private struct InFlight {
        let generation: Int
        let task: Task<[String], Never>
    }

    private var entries: BoundedMemoryCache<Key, Entry>
    private var generations: [Key: Int] = [:]
    private var inFlight: [Key: InFlight] = [:]

    init(capacity: Int = BranchListCache.defaultCapacity) {
        entries = BoundedMemoryCache(capacity: capacity)
    }

    func values(
        for key: Key,
        now: Date = Date(),
        load: @escaping @Sendable () async -> [String]
    ) async -> [String] {
        if let entry = entries.value(for: key), now.timeIntervalSince(entry.createdAt) < Self.ttl {
            return entry.values
        }

        let generation = generations[key, default: 0]
        if let request = inFlight[key], request.generation == generation {
            return await request.task.value
        }

        let task = Task { await load() }
        inFlight[key] = InFlight(generation: generation, task: task)
        let values = await task.value

        if inFlight[key]?.generation == generation {
            inFlight[key] = nil
        }
        if generations[key, default: 0] == generation {
            if let evicted = entries.insert(Entry(values: values, createdAt: now), for: key),
               inFlight[evicted.key] == nil {
                generations[evicted.key] = nil
            }
        } else if inFlight[key] == nil && entries.keys.contains(key) == false {
            generations[key] = nil
        }
        return values
    }

    func invalidate(repositoryURL: URL) {
        let keys = entries.keys.filter { $0.repositoryURL == repositoryURL }
        let inFlightKeys = inFlight.keys.filter { $0.repositoryURL == repositoryURL }
        for key in Set(keys + inFlightKeys) {
            invalidate(key)
        }
    }

    func invalidateRemote(repositoryURL: URL, remote: String) {
        invalidate(.remote(repositoryURL, remote))
    }

    func invalidateRemotes(repositoryURL: URL) {
        let keys = entries.keys.filter {
            $0.repositoryURL == repositoryURL && isRemoteKey($0)
        }
        let inFlightKeys = inFlight.keys.filter {
            $0.repositoryURL == repositoryURL && isRemoteKey($0)
        }
        for key in Set(keys + inFlightKeys) {
            invalidate(key)
        }
    }

    func removeAll() {
        let keys = Set(entries.keys).union(inFlight.keys)
        for key in keys {
            invalidate(key)
        }
    }

    private func invalidate(_ key: Key) {
        entries.removeValue(forKey: key)
        if let request = inFlight.removeValue(forKey: key) {
            generations[key, default: 0] += 1
            request.task.cancel()
        } else {
            generations[key] = nil
        }
    }

    private func isRemoteKey(_ key: Key) -> Bool {
        if case .remote = key {
            return true
        }
        return false
    }
}
