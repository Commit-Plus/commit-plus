// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Stores user intent before any asynchronous preparation starts.
struct RepositorySheetRequest<Input>: Identifiable {
    let id = UUID()
    let input: Input
}
