// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct RepositoryPickerListItem: Identifiable, Equatable {
    let id: String
    var depth = 0
    var repository: RecentRepository?
    var bookmark: RepositoryBookmark?
    var folder: URL?
    var count = 0
    var expanded = false
    var state: RepoPickerRowState?
    var icon = "code-branch"
    var starred = false
    var syncing = false
    var selected = false
    var warnings: [RepositoryBookmark] = []
}
