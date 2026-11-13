// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct RevisionBrowserSnapshot: Sendable {
    let commitID: String
    let subject: String
}
