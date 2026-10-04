// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

@MainActor
final class CustomActionStore: ObservableObject {
    static let actionsKey = "customActions.catalog.v1"
    static let trustKey = "customActions.trust.v1"
    static let executableOverridesKey = "customActions.executableOverrides.v1"

    @Published private(set) var actions: [CustomActionDefinition]
    @Published private(set) var syncError: String?

    private let userDefaults: UserDefaults
    private let cloudStore: CustomActionCloudStore?
    private var cloudObservation: ObservationToken?
    private var activeUID: String?
    private var trustedFingerprints: [String: String]
    private var executableOverrides: [String: String]

    init(
        userDefaults: UserDefaults = .standard,
        cloudStore: CustomActionCloudStore? = nil
    ) {
        self.userDefaults = userDefaults
        self.cloudStore = cloudStore
        actions = Self.decode([CustomActionDefinition].self, from: userDefaults.data(forKey: Self.actionsKey)) ?? []
        trustedFingerprints = Self.decode([String: String].self, from: userDefaults.data(forKey: Self.trustKey)) ?? [:]
        executableOverrides = Self.decode([String: String].self, from: userDefaults.data(forKey: Self.executableOverridesKey)) ?? [:]
        normalizeAndSave()
    }

    func updateCloudSession(uid: String?, enabled: Bool) async {
        if enabled, let uid, activeUID == uid, cloudObservation != nil { return }
        cloudObservation?.cancel()
        cloudObservation = nil
        activeUID = nil
        syncError = nil

        guard enabled, let uid, let cloudStore else { return }
        activeUID = uid
        do {
            let remote = try await cloudStore.load(uid: uid)
            guard activeUID == uid else { return }
            if remote.isEmpty, !actions.isEmpty {
                for action in actions {
                    try await cloudStore.upsert(action, uid: uid)
                }
            } else {
                let localByID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
                let remoteIDs = Set(remote.map(\.id))
                var merged = remote
                merged.append(contentsOf: actions.filter { !remoteIDs.contains($0.id) })
                applyRemote(merged)
                for action in localByID.values where !remoteIDs.contains(action.id) {
                    try await cloudStore.upsert(action, uid: uid)
                }
            }
            beginObserving(uid: uid)
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
        guard let uid = activeUID, let cloudStore else { return }
        Task { @MainActor in
            do { try await cloudStore.upsert(normalized, uid: uid) }
            catch { self.syncError = error.localizedDescription }
        }
    }

    func delete(_ action: CustomActionDefinition) {
        actions.removeAll { $0.id == action.id }
        trustedFingerprints[action.id.uuidString] = nil
        executableOverrides[action.id.uuidString] = nil
        normalizeAndSave()
        saveTrustedFingerprints()
        saveExecutableOverrides()
        guard let uid = activeUID, let cloudStore else { return }
        Task { @MainActor in
            do { try await cloudStore.delete(id: action.id, uid: uid) }
            catch { self.syncError = error.localizedDescription }
        }
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
        guard let uid = activeUID, let cloudStore else { return }
        let snapshot = actions
        Task { @MainActor in
            do { try await cloudStore.updateOrder(snapshot, uid: uid) }
            catch { self.syncError = error.localizedDescription }
        }
    }

    private func beginObserving(uid: String) {
        guard let cloudStore else { return }
        cloudObservation = cloudStore.observe(uid: uid) { [weak self] result in
            Task { @MainActor in
                guard let self, self.activeUID == uid else { return }
                switch result {
                case .success(let actions):
                    self.syncError = nil
                    self.applyRemote(actions)
                case .failure(let error):
                    self.syncError = error.localizedDescription
                }
            }
        }
    }

    private func applyRemote(_ remote: [CustomActionDefinition]) {
        actions = remote
        normalizeAndSave()
    }

    private func normalizeAndSave() {
        actions = actions.enumerated().map { index, action in
            var normalized = action
            normalized.sortIndex = index
            return normalized
        }
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

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
