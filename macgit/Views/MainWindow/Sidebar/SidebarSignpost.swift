// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import os

enum SidebarSignpost {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.commitplus.macgit",
        category: "Sidebar"
    )

    static func interval<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return try operation()
    }

    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
