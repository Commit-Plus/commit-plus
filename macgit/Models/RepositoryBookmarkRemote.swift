// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct RepositoryBookmarkRemote: Identifiable, Equatable {
    let name: String
    let identity: RepositoryBookmarkIdentity

    var id: String { name }
}
