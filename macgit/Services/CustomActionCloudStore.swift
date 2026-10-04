// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

@MainActor
protocol CustomActionCloudStore {
    func load(uid: String) async throws -> [CustomActionDefinition]
    func upsert(_ action: CustomActionDefinition, uid: String) async throws
    func delete(id: UUID, uid: String) async throws
    func updateOrder(_ actions: [CustomActionDefinition], uid: String) async throws
}
