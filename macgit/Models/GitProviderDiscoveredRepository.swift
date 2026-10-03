// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct GitProviderDiscoveredRepository: Identifiable, Equatable {
    var name: String
    var cloneURL: String
    var id: String { cloneURL }
}

