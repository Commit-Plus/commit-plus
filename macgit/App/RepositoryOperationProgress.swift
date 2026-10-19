//
//  RepositoryOperationProgress.swift
//  macgit
//

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
import SwiftUI

typealias RepositoryOperationRunner = (_ message: String, _ operation: @escaping () async -> Void) -> Void

struct RepositoryOperationProgressItem: Identifiable, Equatable {
    let id: UUID
    var message: String
    var canCancel: Bool
    var isCancelling: Bool
}

struct RepositoryOperationProgressEvent {
    let id: UUID
    let message: String
    let canCancel: Bool

    init(id: UUID = UUID(), message: String, canCancel: Bool = true) {
        self.id = id
        self.message = message
        self.canCancel = canCancel
    }
}

enum RepositoryBackgroundActivityState: Equatable {
    case queued
    case running
    case failed(summary: String, detail: String)
}

struct RepositoryBackgroundActivityItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    var state: RepositoryBackgroundActivityState

    var isPending: Bool {
        switch state {
        case .queued, .running: true
        case .failed: false
        }
    }
}

enum RepositoryBackgroundActivityOutcome: Equatable {
    case succeeded
    case failed(String)
}

enum RepositoryBackgroundActivityIndicator: Equatable {
    case idle
    case running
    case failed
}

extension Notification.Name {
    static let repositoryOperationProgressBegan = Notification.Name("macgit.repositoryOperationProgressBegan")
    static let repositoryOperationProgressEnded = Notification.Name("macgit.repositoryOperationProgressEnded")
    static let repositoryOperationProgressCancelRequested = Notification.Name("macgit.repositoryOperationProgressCancelRequested")
}

enum RepositoryOperationProgressBus {
    @discardableResult
    static func begin(message: String, canCancel: Bool = true) -> UUID {
        let event = RepositoryOperationProgressEvent(message: message, canCancel: canCancel)
        NotificationCenter.default.post(
            name: .repositoryOperationProgressBegan,
            object: nil,
            userInfo: ["event": event]
        )
        return event.id
    }

    static func end(_ id: UUID) {
        NotificationCenter.default.post(
            name: .repositoryOperationProgressEnded,
            object: nil,
            userInfo: ["id": id]
        )
    }

    static func requestCancel(_ id: UUID) {
        NotificationCenter.default.post(
            name: .repositoryOperationProgressCancelRequested,
            object: nil,
            userInfo: ["id": id]
        )
    }
}

@MainActor
final class RepositoryOperationProgress: ObservableObject {
    @Published private(set) var activeOperation: RepositoryOperationProgressItem?

    private var orderedOperationIDs: [UUID] = []
    private var operationsByID: [UUID: RepositoryOperationProgressItem] = [:]
    private var cancelHandlers: [UUID: () -> Void] = [:]

    func run(message: String, operation: @escaping () async -> Void) {
        let id = begin(message: message, canCancel: true)
        let task = Task {
            await operation()
            await MainActor.run {
                self.end(id)
            }
        }
        cancelHandlers[id] = {
            task.cancel()
        }
        updateActiveOperation()
    }

    func begin(_ event: RepositoryOperationProgressEvent) {
        begin(id: event.id, message: event.message, canCancel: event.canCancel)
    }

    @discardableResult
    func begin(id: UUID = UUID(), message: String, canCancel: Bool = true) -> UUID {
        let item = RepositoryOperationProgressItem(
            id: id,
            message: message,
            canCancel: canCancel,
            isCancelling: false
        )
        operationsByID[id] = item
        orderedOperationIDs.removeAll { $0 == id }
        orderedOperationIDs.append(id)
        updateActiveOperation()
        return id
    }

    func end(_ id: UUID) {
        operationsByID[id] = nil
        cancelHandlers[id] = nil
        orderedOperationIDs.removeAll { $0 == id }
        updateActiveOperation()
    }

    func requestCancel(_ id: UUID) {
        guard var item = operationsByID[id] else { return }
        item.isCancelling = true
        operationsByID[id] = item
        updateActiveOperation()
        cancelHandlers[id]?()
    }

    func cancelActiveOperation() {
        guard let activeOperation, activeOperation.canCancel else { return }
        requestCancel(activeOperation.id)
    }

    private func updateActiveOperation() {
        activeOperation = orderedOperationIDs.reversed().compactMap { operationsByID[$0] }.first
    }

    // MARK: - Background lane

    /// Background actions run one at a time per window without the blocking overlay.
    /// They never affect `activeOperation`, so foreground guards are unchanged.
    @Published private(set) var backgroundItems: [RepositoryBackgroundActivityItem] = []

    private var backgroundOperations: [UUID: () async -> RepositoryBackgroundActivityOutcome] = [:]
    private var backgroundDrainTask: Task<Void, Never>?
    private var backgroundDrainGeneration = 0
    private var backgroundIdleWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    var backgroundIndicator: RepositoryBackgroundActivityIndicator {
        if hasPendingBackgroundWork { return .running }
        if !backgroundItems.isEmpty { return .failed }
        return .idle
    }

    var hasPendingBackgroundWork: Bool {
        backgroundItems.contains(where: \.isPending)
    }

    @discardableResult
    func runInBackground(
        title: String,
        operation: @escaping () async -> RepositoryBackgroundActivityOutcome
    ) -> UUID {
        let id = UUID()
        backgroundItems.append(RepositoryBackgroundActivityItem(id: id, title: title, state: .queued))
        backgroundOperations[id] = operation
        startBackgroundDrainIfNeeded()
        return id
    }

    func dismissBackgroundItem(id: UUID) {
        guard let index = backgroundItems.firstIndex(where: { $0.id == id }),
              !backgroundItems[index].isPending else { return }
        backgroundItems.remove(at: index)
    }

    /// Suspends until no background action is queued or running. Returns early when cancelled.
    func waitForBackgroundIdle() async {
        guard hasPendingBackgroundWork, !Task.isCancelled else { return }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if !hasPendingBackgroundWork || Task.isCancelled {
                    continuation.resume()
                } else {
                    backgroundIdleWaiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.backgroundIdleWaiters.removeValue(forKey: waiterID)?.resume()
            }
        }
    }

    func cancelAllBackground() {
        backgroundDrainGeneration += 1
        backgroundDrainTask?.cancel()
        backgroundDrainTask = nil
        backgroundOperations.removeAll()
        backgroundItems.removeAll()
        resumeBackgroundIdleWaitersIfIdle()
    }

    nonisolated static func backgroundErrorSummary(_ message: String) -> String {
        let line = message
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !line.isEmpty else { return "Unknown error" }
        let limit = 140
        guard line.count > limit else { return line }
        return String(line.prefix(limit - 1)) + "…"
    }

    private func startBackgroundDrainIfNeeded() {
        guard backgroundDrainTask == nil else { return }
        let generation = backgroundDrainGeneration
        backgroundDrainTask = Task {
            await drainBackgroundQueue(generation: generation)
        }
    }

    private func drainBackgroundQueue(generation: Int) async {
        while generation == backgroundDrainGeneration,
              let index = backgroundItems.firstIndex(where: { $0.state == .queued }) {
            let id = backgroundItems[index].id
            guard let operation = backgroundOperations.removeValue(forKey: id) else {
                backgroundItems.remove(at: index)
                continue
            }
            backgroundItems[index].state = .running
            let outcome = await operation()
            guard generation == backgroundDrainGeneration,
                  let current = backgroundItems.firstIndex(where: { $0.id == id }) else { break }
            switch outcome {
            case .succeeded:
                backgroundItems.remove(at: current)
            case .failed(let message):
                backgroundItems[current].state = .failed(
                    summary: Self.backgroundErrorSummary(message),
                    detail: message
                )
            }
        }
        guard generation == backgroundDrainGeneration else { return }
        backgroundDrainTask = nil
        resumeBackgroundIdleWaitersIfIdle()
    }

    private func resumeBackgroundIdleWaitersIfIdle() {
        guard !hasPendingBackgroundWork else { return }
        let waiters = backgroundIdleWaiters.values
        backgroundIdleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

struct RepositoryOperationOverlayView: View {
    let operation: RepositoryOperationProgressItem
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(operation.isCancelling ? "Cancelling..." : operation.message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        IndeterminateRepositoryProgressBar()
                            .frame(height: 4)
                    }

                    Spacer(minLength: 16)

                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!operation.canCancel || operation.isCancelling)
                    .help("Cancel the current operation")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.regularMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.separator)
                        .frame(height: 0.5)
                }

                Spacer()
            }
        }
        .transition(.opacity)
        .zIndex(1000)
    }
}

private struct IndeterminateRepositoryProgressBar: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let segmentWidth = max(width * 0.28, 48)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.22))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: segmentWidth)
                    .offset(x: isAnimating ? width : -segmentWidth)
                    .animation(
                        .linear(duration: 1.6).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            .clipShape(Capsule())
            .onAppear {
                isAnimating = true
            }
        }
    }
}
