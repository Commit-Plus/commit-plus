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

@MainActor
final class CommitPlusAIUsageController: ObservableObject {
    nonisolated static let cacheDuration: TimeInterval = 5 * 60

    enum State: Equatable {
        case idle, loading
        case loaded(CommitPlusAIAllowance)
        case unavailable(String)
    }
    @Published private(set) var state: State = .idle
    private(set) var uid: String?
    private var generation = UUID()
    private var pending: Task<CommitPlusAIAllowance, Error>?
    private var loadedAt: Date?
    private let now: () -> Date
    private let cacheDuration: TimeInterval
    var loader: (@Sendable () async throws -> CommitPlusAIAllowance)?

    init(cacheDuration: TimeInterval = CommitPlusAIUsageController.cacheDuration,
         now: @escaping () -> Date = { .now }) {
        self.cacheDuration = cacheDuration
        self.now = now
    }

    func setSession(uid: String?) {
        guard self.uid != uid else { return }
        self.uid = uid
        generation = UUID()
        pending?.cancel()
        pending = nil
        loadedAt = nil
        state = .idle
    }
    func accept(_ allowance: CommitPlusAIAllowance, uid: String) {
        guard self.uid == uid else { return }
        // A terminal inference result supersedes any earlier allowance read.
        generation = UUID()
        pending?.cancel()
        pending = nil
        state = .loaded(allowance)
        loadedAt = now()
    }
    func refresh(force: Bool = false) async {
        guard uid != nil else { state = .unavailable(CommitPlusAIError.signedOut.localizedDescription); return }
        if !force, case .loaded = state, let loadedAt,
           now().timeIntervalSince(loadedAt) < cacheDuration { return }
        let epoch = generation
        let task: Task<CommitPlusAIAllowance, Error>
        if let pending { task = pending }
        else {
            guard let loader else { state = .unavailable(CommitPlusAIError.unavailable.localizedDescription); return }
            task = Task { try await loader() }
            pending = task
            state = .loading
        }
        do {
            let allowance = try await task.value
            guard generation == epoch else { return }
            state = .loaded(allowance)
            loadedAt = now()
        } catch {
            guard generation == epoch else { return }
            state = .unavailable(error.localizedDescription)
        }
        if generation == epoch { pending = nil }
    }
    var availability: AIProviderAvailability {
        switch state {
        case .idle, .loading: .checking
        case .loaded(let allowance): allowance.availability
        case .unavailable(let message): .unavailable(message)
        }
    }
}
