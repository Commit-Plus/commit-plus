// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct LocalDataTransaction {
    private(set) var records: [String: [String: Data]]
    private(set) var changes: [(String, String, Data?)] = []

    func value<T: Decodable>(_ type: T.Type, in collection: String, id: String) throws -> T? {
        try records[collection]?[id].map { try JSONDecoder().decode(type, from: $0) }
    }

    func values<T: Decodable>(_ type: T.Type, in collection: String) throws -> [String: T] {
        try (records[collection] ?? [:]).mapValues { try JSONDecoder().decode(type, from: $0) }
    }

    mutating func set<T: Encodable>(_ value: T, in collection: String, id: String) throws {
        let data = try JSONEncoder().encode(value)
        records[collection, default: [:]][id] = data
        changes.append((collection, id, data))
    }

    mutating func remove(in collection: String, id: String) {
        records[collection]?[id] = nil
        changes.append((collection, id, nil))
    }
}
