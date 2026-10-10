// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import os

nonisolated enum DiffSignpost {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "macgit",
        category: "DiffView"
    )

    @inline(__always)
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}

#if DEBUG
@MainActor
enum DiffRenderStats {
    static var headerHostAssignments = 0
    static var canvasDraws = 0
    static var lineBuilds = 0
    static var longLinePreparations = 0

    static func reset() {
        headerHostAssignments = 0
        canvasDraws = 0
        lineBuilds = 0
        longLinePreparations = 0
    }
}
#endif
