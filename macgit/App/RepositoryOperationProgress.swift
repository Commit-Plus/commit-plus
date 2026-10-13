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
