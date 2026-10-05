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

    @Published private(set) var actions: [CustomActionDefinition]
    @Published private(set) var syncError: String?

    private let userDefaults: UserDefaults
    private let cloudStore: CustomActionCloudStore?
    private var activeUID: String?
    private var catalogUID: String?
    private var sessionGeneration = 0
    private var mutationVersions: [String: Int] = [:]
    private var periodicSyncTask: Task<Void, Never>?
    private var isSyncing = false
    private var sessionObservation: AnyCancellable?
    private var trustedFingerprints: [String: String]
    private var executableOverrides: [String: String]
    private var pendingUpserts: Set<String>
    private var pendingDeletions: Set<String>

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
        normalizeAndSave()
    }

    func observeSession(accountController: AccountSessionController, appState: AppState) {
        let accountUID = accountController.$state.map { state -> String? in
            guard case .authenticated(let account) = state else { return nil }
            return account.uid
        }
        let session = accountUID.combineLatest(appState.$syncEnabled)
            .removeDuplicates { previous, current in
                previous.0 == current.0 && previous.1 == current.1
            }
        sessionObservation = session.sink { [weak self] value in
            guard let self else { return }
            let generation = self.beginCloudSession(uid: value.0, enabled: value.1)
            Task { @MainActor [weak self] in
                await self?.startCloudSession(generation: generation)
            }
        }
    }

    func updateCloudSession(uid: String?, enabled: Bool) async {
        let generation = beginCloudSession(uid: uid, enabled: enabled)
        await startCloudSession(generation: generation)
    }

    private func beginCloudSession(uid: String?, enabled: Bool) -> Int {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        activeUID = enabled ? uid : nil
        syncError = nil
        if catalogUID != uid {
            catalogUID = uid
            actions = Self.decode([CustomActionDefinition].self, from: userDefaults.data(forKey: scopedKey(Self.actionsKey))) ?? []
            trustedFingerprints = Self.decode([String: String].self, from: userDefaults.data(forKey: scopedKey(Self.trustKey))) ?? [:]
            executableOverrides = Self.decode([String: String].self, from: userDefaults.data(forKey: scopedKey(Self.executableOverridesKey))) ?? [:]
            pendingUpserts = Self.decode(Set<String>.self, from: userDefaults.data(forKey: scopedKey(Self.pendingUpsertsKey))) ?? []
            pendingDeletions = Self.decode(Set<String>.self, from: userDefaults.data(forKey: scopedKey(Self.pendingDeletionsKey))) ?? []
            mutationVersions = [:]
        }
        return generation
    }

    private func startCloudSession(generation: Int) async {
        guard generation == sessionGeneration, activeUID != nil, cloudStore != nil else { return }
        await syncNow()
        guard generation == sessionGeneration else { return }
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
        let generation = sessionGeneration
        isSyncing = true
        defer {
            isSyncing = false
            if generation != sessionGeneration {
                Task { @MainActor [weak self] in await self?.syncNow() }
            }
        }
        do {
            for idString in Array(pendingDeletions) {
                guard let id = UUID(uuidString: idString) else { continue }
                let version = mutationVersions[idString, default: 0]
                try await cloudStore.delete(id: id, uid: uid)
                guard generation == sessionGeneration else { return }
                if mutationVersions[idString, default: 0] == version {
                    pendingDeletions.remove(idString)
                    savePendingMutations()
                }
            }
            for idString in Array(pendingUpserts) {
                guard let id = UUID(uuidString: idString),
                      let action = actions.first(where: { $0.id == id }) else { continue }
                let version = mutationVersions[idString, default: 0]
                try await cloudStore.upsert(action, uid: uid)
                guard generation == sessionGeneration else { return }
                if mutationVersions[idString, default: 0] == version {
                    pendingUpserts.remove(idString)
                    savePendingMutations()
                }
            }
            let remote = try await cloudStore.load(uid: uid)
            guard generation == sessionGeneration else { return }
            applyRemote(remote)
            syncError = nil
        } catch {
            guard generation == sessionGeneration else { return }
            syncError = error.localizedDescription
        }
    }

    private func scopedKey(_ key: String) -> String {
        guard let catalogUID else { return key }
        return key + ".account." + Data(catalogUID.utf8).base64EncodedString()
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

    func saveEditedAction(_ action: CustomActionDefinition, original: CustomActionDefinition?) {
        var definition = action
        if let original, let stored = actions.first(where: { $0.id == action.id }),
           action.executablePath == original.executablePath,
           action.sourceKind == original.sourceKind {
            definition.executablePath = stored.executablePath
        } else {
            setExecutableOverride(nil, for: action)
        }
        upsert(definition)
    }

    func delete(_ action: CustomActionDefinition) {
        actions.removeAll { $0.id == action.id }
        trustedFingerprints[action.id.uuidString] = nil
        executableOverrides[action.id.uuidString] = nil
        normalizeAndSave()
        saveTrustedFingerprints()
        saveExecutableOverrides()
        mutationVersions[action.id.uuidString, default: 0] &+= 1
        pendingUpserts.remove(action.id.uuidString)
        pendingDeletions.insert(action.id.uuidString)
        savePendingMutations()
    }

    func duplicate(_ action: CustomActionDefinition) {
        guard let original = actions.first(where: { $0.id == action.id }) else { return }
        let copy = original.duplicated
        let trustOnThisMac = isTrusted(original)
        if let override = executableOverrides[original.id.uuidString] {
            executableOverrides[copy.id.uuidString] = override
            saveExecutableOverrides()
        }
        upsert(copy, trustOnThisMac: trustOnThisMac)
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
        for action in actions { mutationVersions[action.id.uuidString, default: 0] &+= 1 }
        pendingUpserts.formUnion(actions.map { $0.id.uuidString })
        savePendingMutations()
    }

    private func applyRemote(_ remote: [CustomActionDefinition]) {
        let localPending = actions.filter { pendingUpserts.contains($0.id.uuidString) }
        let remoteUnchanged = remote.filter {
            !pendingDeletions.contains($0.id.uuidString) && !pendingUpserts.contains($0.id.uuidString)
        }
        let normalizedActions = normalized((remoteUnchanged + localPending).sorted { $0.sortIndex < $1.sortIndex })
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
            userDefaults.set(data, forKey: scopedKey(Self.actionsKey))
        }
    }

    private func saveTrustedFingerprints() {
        if let data = try? JSONEncoder().encode(trustedFingerprints) {
            userDefaults.set(data, forKey: scopedKey(Self.trustKey))
        }
    }

    private func saveExecutableOverrides() {
        if let data = try? JSONEncoder().encode(executableOverrides) {
            userDefaults.set(data, forKey: scopedKey(Self.executableOverridesKey))
        }
    }

    private func markPendingUpsert(_ id: UUID) {
        mutationVersions[id.uuidString, default: 0] &+= 1
        pendingDeletions.remove(id.uuidString)
        pendingUpserts.insert(id.uuidString)
        savePendingMutations()
    }

    private func savePendingMutations() {
        if let data = try? JSONEncoder().encode(pendingUpserts) {
            userDefaults.set(data, forKey: scopedKey(Self.pendingUpsertsKey))
        }
        if let data = try? JSONEncoder().encode(pendingDeletions) {
            userDefaults.set(data, forKey: scopedKey(Self.pendingDeletionsKey))
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
