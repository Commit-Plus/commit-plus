// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct YourRepository: Identifiable, Equatable, Sendable {
    var id: URL { url }
    let url: URL
    let rootURL: URL

    var name: String { url.lastPathComponent }
}
