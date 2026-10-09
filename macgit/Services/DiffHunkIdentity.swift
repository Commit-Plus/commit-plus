// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated enum DiffHunkIdentity {
    static func make(oldStart: Int, newStart: Int, occurrence: Int) -> UUID {
        var first = Hasher()
        first.combine(oldStart)
        first.combine(newStart)
        var second = Hasher()
        second.combine(occurrence)
        second.combine(0x48554e4b)
        return uuid(high: first.finalize(), low: second.finalize())
    }

    private static func uuid(high: Int, low: Int) -> UUID {
        let high = UInt64(bitPattern: Int64(high))
        let low = UInt64(bitPattern: Int64(low))
        func byte(_ value: UInt64, _ index: Int) -> UInt8 {
            UInt8(truncatingIfNeeded: value >> (index * 8))
        }
        return UUID(uuid: (
            byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3),
            byte(high, 4), byte(high, 5), byte(high, 6), byte(high, 7),
            byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
            byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)
        ))
    }
}
