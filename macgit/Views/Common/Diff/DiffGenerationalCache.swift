// SPDX-License-Identifier: AGPL-3.0-or-later

nonisolated struct DiffGenerationalCache<Key: Hashable, Value> {
    private let capacity: Int
    private let generationCapacity: Int
    private var current: [Key: Value] = [:]
    private var previous: [Key: Value] = [:]

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        generationCapacity = max(1, (max(1, capacity) + 1) / 2)
    }

    var count: Int { current.count + previous.count }

    mutating func value(for key: Key) -> Value? {
        if let value = current[key] {
            return value
        }
        guard let value = previous.removeValue(forKey: key) else {
            return nil
        }
        makeRoomIfNeeded()
        current[key] = value
        trimToCapacity()
        return value
    }

    mutating func insert(_ value: Value, for key: Key) {
        previous.removeValue(forKey: key)
        if current[key] == nil {
            makeRoomIfNeeded()
        }
        current[key] = value
        trimToCapacity()
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        current.removeAll(keepingCapacity: keepingCapacity)
        previous.removeAll(keepingCapacity: keepingCapacity)
    }

    private mutating func makeRoomIfNeeded() {
        guard current.count >= generationCapacity else { return }
        previous = current
        current.removeAll(keepingCapacity: true)
    }

    private mutating func trimToCapacity() {
        while count > capacity, let key = previous.keys.first {
            previous.removeValue(forKey: key)
        }
    }
}
