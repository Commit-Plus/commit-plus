//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Combine
import Foundation

enum InitialSettingsChoice {
    case useCloud
    case keepThisMac
    case cancel
}

enum SettingsSyncStatus: Equatable {
    case off
    case locked
    case starting
    case needsInitialChoice(AppSettingsSnapshot)
    case syncing
    case paused
    case failed(String)
}

@MainActor
protocol SettingsSyncDebounceScheduling: AnyObject {
    func schedule(_ operation: @escaping @MainActor () async -> Void) -> ObservationToken
}

@MainActor
final class TaskSettingsSyncScheduler: SettingsSyncDebounceScheduling {
    func schedule(_ operation: @escaping @MainActor () async -> Void) -> ObservationToken {
        let task = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await operation()
        }
        return SettingsSyncTaskToken(task: task)
    }
}

private final class SettingsSyncTaskToken: ObservationToken {
    private var task: Task<Void, Never>?

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

@MainActor
final class SettingsSyncService: ObservableObject {
    @Published private(set) var status: SettingsSyncStatus = .off

    private let store: CloudSettingsStore
    private let currentSnapshot: () -> AppSettingsSnapshot
    private let applySnapshot: (AppSettingsSnapshot) -> Void
    private let setSyncEnabled: (Bool) -> Void
    private let debounceScheduler: SettingsSyncDebounceScheduling

    private var pendingDebounce: ObservationToken?
    private var activeUID: String?
    private var isSessionActive = false
    private var pendingCloudSnapshot: AppSettingsSnapshot?
    private var lastKnownCloudSnapshot: AppSettingsSnapshot?
    private var pendingLocalSnapshot: AppSettingsSnapshot?
    private var isApplyingRemote = false
    private var generation = 0

    init(
        store: CloudSettingsStore,
        currentSnapshot: @escaping () -> AppSettingsSnapshot,
        applySnapshot: @escaping (AppSettingsSnapshot) -> Void,
        setSyncEnabled: @escaping (Bool) -> Void,
        debounceScheduler: SettingsSyncDebounceScheduling? = nil
    ) {
        self.store = store
        self.currentSnapshot = currentSnapshot
        self.applySnapshot = applySnapshot
        self.setSyncEnabled = setSyncEnabled
        self.debounceScheduler = debounceScheduler ?? TaskSettingsSyncScheduler()
    }

    func updateEligibility(
        uid: String?,
        enabled: Bool
    ) async {
        guard let uid else {
            deactivate(status: .off)
            return
        }

        guard enabled else {
            deactivate(status: .off)
            return
        }

        if activeUID == uid,
           isSessionActive || pendingCloudSnapshot != nil {
            return
        }

        deactivate(status: .starting)
        activeUID = uid
        let currentGeneration = generation

        do {
            let cloudSnapshot = try await store.load(uid: uid)
            guard isCurrent(uid: uid, generation: currentGeneration) else { return }

            let localSnapshot = currentSnapshot()
            guard let cloudSnapshot else {
                try await store.save(localSnapshot, uid: uid)
                guard isCurrent(uid: uid, generation: currentGeneration) else { return }
                lastKnownCloudSnapshot = localSnapshot
                beginSession(uid: uid, generation: currentGeneration)
                return
            }

            lastKnownCloudSnapshot = cloudSnapshot
            if cloudSnapshot == localSnapshot {
                beginSession(uid: uid, generation: currentGeneration)
            } else {
                pendingCloudSnapshot = cloudSnapshot
                status = .needsInitialChoice(cloudSnapshot)
            }
        } catch {
            guard isCurrent(uid: uid, generation: currentGeneration) else { return }
            status = .failed(Self.message(for: error))
        }
    }

    func resolveInitialChoice(_ choice: InitialSettingsChoice) async {
        guard let uid = activeUID,
              let cloudSnapshot = pendingCloudSnapshot else { return }
        let currentGeneration = generation

        switch choice {
        case .cancel:
            setSyncEnabled(false)
            deactivate(status: .off)
        case .useCloud:
            pendingCloudSnapshot = nil
            applyRemote(cloudSnapshot)
            beginSession(uid: uid, generation: currentGeneration)
        case .keepThisMac:
            let localSnapshot = currentSnapshot()
            do {
                try await store.save(localSnapshot, uid: uid)
                guard isCurrent(uid: uid, generation: currentGeneration) else { return }
                pendingCloudSnapshot = nil
                lastKnownCloudSnapshot = localSnapshot
                beginSession(uid: uid, generation: currentGeneration)
            } catch {
                guard isCurrent(uid: uid, generation: currentGeneration) else { return }
                status = .failed(Self.message(for: error))
            }
        }
    }

    func localSettingsDidChange(_ snapshot: AppSettingsSnapshot) {
        guard let uid = activeUID,
              isSessionActive,
              !isApplyingRemote else { return }

        // A publisher can deliver the just-applied remote value after
        // applyRemote() clears its synchronous guard. Do not echo that value
        // back to Firestore unless it is also replacing a pending local edit.
        guard snapshot != lastKnownCloudSnapshot || pendingLocalSnapshot != nil else { return }

        pendingLocalSnapshot = snapshot
        pendingDebounce?.cancel()
        let currentGeneration = generation
        pendingDebounce = debounceScheduler.schedule { [weak self] in
            guard let self else { return }
            await self.saveLocalSnapshot(snapshot, uid: uid, generation: currentGeneration)
        }
    }

    private func saveLocalSnapshot(
        _ snapshot: AppSettingsSnapshot,
        uid: String,
        generation currentGeneration: Int
    ) async {
        pendingDebounce = nil
        guard isCurrent(uid: uid, generation: currentGeneration), isSessionActive else { return }
        do {
            try await store.save(snapshot, uid: uid)
            guard isCurrent(uid: uid, generation: currentGeneration) else { return }
            lastKnownCloudSnapshot = snapshot
            if pendingLocalSnapshot == snapshot {
                pendingLocalSnapshot = nil
            }
            status = .syncing
        } catch {
            guard isCurrent(uid: uid, generation: currentGeneration) else { return }
            status = .failed(Self.message(for: error))
        }
    }

    private func beginSession(uid: String, generation currentGeneration: Int) {
        guard isCurrent(uid: uid, generation: currentGeneration) else { return }
        isSessionActive = true
        status = .syncing
    }

    private func applyRemote(_ snapshot: AppSettingsSnapshot) {
        lastKnownCloudSnapshot = snapshot
        isApplyingRemote = true
        applySnapshot(snapshot)
        isApplyingRemote = false
    }

    private func deactivate(status newStatus: SettingsSyncStatus) {
        generation += 1
        pendingDebounce?.cancel()
        pendingDebounce = nil
        activeUID = nil
        isSessionActive = false
        pendingCloudSnapshot = nil
        lastKnownCloudSnapshot = nil
        pendingLocalSnapshot = nil
        isApplyingRemote = false
        status = newStatus
    }

    private func isCurrent(uid: String, generation expectedGeneration: Int) -> Bool {
        activeUID == uid && generation == expectedGeneration
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
