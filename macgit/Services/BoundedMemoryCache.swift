// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Small access-ordered cache for state that must not grow with every
/// repository, branch, filter, or search visited in one app session.
nonisolated struct BoundedMemoryCache<Key: Hashable, Value> {
    let capacity: Int
    private var values: [Key: Value] = [:]
    private var accessOrder: [Key] = []

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var count: Int { values.count }
    var keys: Dictionary<Key, Value>.Keys { values.keys }

    mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    @discardableResult
    mutating func insert(_ value: Value, for key: Key) -> (key: Key, value: Value)? {
        values[key] = value
        touch(key)
        guard values.count > capacity, let evictedKey = accessOrder.first else { return nil }
        accessOrder.removeFirst()
        return values.removeValue(forKey: evictedKey).map { (evictedKey, $0) }
    }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        accessOrder.removeAll { $0 == key }
        return values.removeValue(forKey: key)
    }

    mutating func removeAll() {
        values.removeAll()
        accessOrder.removeAll()
    }

    private mutating func touch(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}
