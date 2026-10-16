// SPDX-License-Identifier: AGPL-3.0-or-later
enum RepositoryPickerListMode: String, CaseIterable {
    case plain
    case tree

    var icon: String { self == .plain ? "list.bullet" : "list.bullet.indent" }
}
