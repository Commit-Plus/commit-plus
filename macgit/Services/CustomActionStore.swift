// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

@MainActor
final class CustomActionStore: ObservableObject {
    static let actionsKey = "customActions.catalog.v1"
    static let trustKey = "customActions.trust.v1"
    static let executableOverridesKey = "customActions.executableOverrides.v1"
    static let pendingUpsertsKey = "customActions.pendingUpserts.v1"
    static let pendingDeletionsKey = "customActions.pendingDeletions.v1"
    static let initializedCloudUIDsKey = "customActions.initializedCloudUIDs.v1"

    @Published private(set) var actions: [CustomActionDefinition]
    @Published private(set) var syncError: String?

    private let userDefaults: UserDefaults
    private let cloudStore: CustomActionCloudStore?
    private var activeUID: String?
    private var periodicSyncTask: Task<Void, Never>?
    private var isSyncing = false
    private var trustedFingerprints: [String: String]
    private var executableOverrides: [String: String]
    private var pendingUpserts: Set<String>
    private var pendingDeletions: Set<String>
    private var initializedCloudUIDs: Set<String>

    init(
        userDefaults: UserDefaults = .standard,
        cloudStore: CustomActionCloudStore? = nil
    ) {
        self.userDefaults = userDefaults
        self.cloudStore = cloudStore
        actions = Self.decode([CustomActionDefinition].self, from: userDefaults.data(forKey: Self.actionsKey)) ?? []
        trustedFingerprints = Self.decode([String: String].self, from: userDefaults.data(forKey: Self.trustKey)) ?? [:]
        executableOverrides = Self.decode([String: String].self, from: userDefaults.data(forKey: Self.executableOverridesKey)) ?? [:]
        pendingUpserts = Self.decode(Set<String>.self, from: userDefaults.data(forKey: Self.pendingUpsertsKey)) ?? []
        pendingDeletions = Self.decode(Set<String>.self, from: userDefaults.data(forKey: Self.pendingDeletionsKey)) ?? []
        initializedCloudUIDs = Self.decode(Set<String>.self, from: userDefaults.data(forKey: Self.initializedCloudUIDsKey)) ?? []
        normalizeAndSave()
    }

    func updateCloudSession(uid: String?, enabled: Bool) async {
        if enabled, let uid, activeUID == uid, periodicSyncTask != nil { return }
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        activeUID = nil
        syncError = nil

        guard enabled, let uid, cloudStore != nil else { return }
        activeUID = uid
        await syncNow()
        periodicSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await self?.syncNow()
            }
        }
    }

    func syncNow() async {
        guard !isSyncing, let uid = activeUID, let cloudStore else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            for idString in Array(pendingDeletions) {
                guard let id = UUID(uuidString: idString) else { continue }
                try await cloudStore.delete(id: id, uid: uid)
                pendingDeletions.remove(idString)
                savePendingMutations()
            }

            for idString in Array(pendingUpserts) {
                guard let id = UUID(uuidString: idString),
                      let action = actions.first(where: { $0.id == id }) else {
                    pendingUpserts.remove(idString)
                    continue
                }
                try await cloudStore.upsert(action, uid: uid)
                pendingUpserts.remove(idString)
                savePendingMutations()
            }

            var remote = try await cloudStore.load(uid: uid)
            guard activeUID == uid else { return }
            if !initializedCloudUIDs.contains(uid) {
                let remoteIDs = Set(remote.map(\.id))
                let localOnly = actions.filter { !remoteIDs.contains($0.id) }
                for action in localOnly {
                    try await cloudStore.upsert(action, uid: uid)
                }
                remote.append(contentsOf: localOnly)
                initializedCloudUIDs.insert(uid)
                saveInitializedCloudUIDs()
            }
            applyRemote(remote)
            syncError = nil
        } catch {
            guard activeUID == uid else { return }
            syncError = error.localizedDescription
        }
    }

    func action(id: UUID) -> CustomActionDefinition? {
        actions.first { $0.id == id }.map(effectiveAction)
    }

    func effectiveAction(_ action: CustomActionDefinition) -> CustomActionDefinition {
        guard let override = executableOverrides[action.id.uuidString] else { return action }
        var resolved = action
        resolved.executablePath = override
        return resolved
    }

    func isTrusted(_ action: CustomActionDefinition) -> Bool {
        trustedFingerprints[action.id.uuidString] == effectiveAction(action).trustFingerprint
    }

    func trust(_ action: CustomActionDefinition) {
        trustedFingerprints[action.id.uuidString] = effectiveAction(action).trustFingerprint
        saveTrustedFingerprints()
        objectWillChange.send()
    }

    func setExecutableOverride(_ path: String?, for action: CustomActionDefinition) {
        if let path, !path.isEmpty {
            executableOverrides[action.id.uuidString] = path
        } else {
            executableOverrides[action.id.uuidString] = nil
        }
        saveExecutableOverrides()
        trustedFingerprints[action.id.uuidString] = nil
        saveTrustedFingerprints()
        objectWillChange.send()
    }

    func upsert(_ action: CustomActionDefinition, trustOnThisMac: Bool = true) {
        var normalized = action
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            normalized.sortIndex = actions[index].sortIndex
            actions[index] = normalized
        } else {
            normalized.sortIndex = actions.count
            actions.append(normalized)
        }
        normalizeAndSave()
        if trustOnThisMac { trust(normalized) }
        markPendingUpsert(normalized.id)
    }

    func delete(_ action: CustomActionDefinition) {
        actions.removeAll { $0.id == action.id }
        trustedFingerprints[action.id.uuidString] = nil
        executableOverrides[action.id.uuidString] = nil
        normalizeAndSave()
        saveTrustedFingerprints()
        saveExecutableOverrides()
        pendingUpserts.remove(action.id.uuidString)
        pendingDeletions.insert(action.id.uuidString)
        savePendingMutations()
    }

    func duplicate(_ action: CustomActionDefinition) {
        upsert(action.duplicated)
    }

    func setEnabled(_ enabled: Bool, for action: CustomActionDefinition) {
        var updated = action
        updated.isEnabled = enabled
        upsert(updated, trustOnThisMac: false)
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        let orderedOffsets = fromOffsets.sorted()
        let movingActions = orderedOffsets.map { actions[$0] }
        for offset in orderedOffsets.reversed() {
            actions.remove(at: offset)
        }
        let removedBeforeDestination = orderedOffsets.count { $0 < toOffset }
        let insertionIndex = min(max(0, toOffset - removedBeforeDestination), actions.count)
        actions.insert(contentsOf: movingActions, at: insertionIndex)
        normalizeAndSave()
        pendingUpserts.formUnion(actions.map { $0.id.uuidString })
        savePendingMutations()
    }

    private func applyRemote(_ remote: [CustomActionDefinition]) {
        let normalizedActions = normalized(remote)
        guard normalizedActions != actions else { return }
        actions = normalizedActions
        saveActions()
    }

    private func normalizeAndSave() {
        let normalizedActions = normalized(actions)
        if normalizedActions != actions {
            actions = normalizedActions
        }
        saveActions()
    }

    private func normalized(_ actions: [CustomActionDefinition]) -> [CustomActionDefinition] {
        actions.enumerated().map { index, action in
            var normalized = action
            normalized.sortIndex = index
            return normalized
        }
    }

    private func saveActions() {
        if let data = try? JSONEncoder().encode(actions) {
            userDefaults.set(data, forKey: Self.actionsKey)
        }
    }

    private func saveTrustedFingerprints() {
        if let data = try? JSONEncoder().encode(trustedFingerprints) {
            userDefaults.set(data, forKey: Self.trustKey)
        }
    }

    private func saveExecutableOverrides() {
        if let data = try? JSONEncoder().encode(executableOverrides) {
            userDefaults.set(data, forKey: Self.executableOverridesKey)
        }
    }

    private func markPendingUpsert(_ id: UUID) {
        pendingDeletions.remove(id.uuidString)
        pendingUpserts.insert(id.uuidString)
        savePendingMutations()
    }

    private func savePendingMutations() {
        if let data = try? JSONEncoder().encode(pendingUpserts) {
            userDefaults.set(data, forKey: Self.pendingUpsertsKey)
        }
        if let data = try? JSONEncoder().encode(pendingDeletions) {
            userDefaults.set(data, forKey: Self.pendingDeletionsKey)
        }
    }

    private func saveInitializedCloudUIDs() {
        if let data = try? JSONEncoder().encode(initializedCloudUIDs) {
            userDefaults.set(data, forKey: Self.initializedCloudUIDsKey)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
