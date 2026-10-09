// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct FileLineChangeCount: Equatable, Sendable {
    let added: Int
    let removed: Int
}
