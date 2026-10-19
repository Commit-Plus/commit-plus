// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

@MainActor
final class AppNotificationController: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var pendingBranchCleanup: AppNotification?

    private let dataStore: LocalDataStore
    private let calendar: Calendar
    private var hasLoaded = false
    private static let notificationCollection = "appNotifications"
    private static let dailyCheckCollection = "appNotificationDailyChecks"

    init(dataStore: LocalDataStore? = nil, calendar: Calendar = .current) {
        self.dataStore = dataStore ?? .shared
        self.calendar = calendar
    }

    var unreadCount: Int {
        notifications.count { $0.readAt == nil }
    }

    func load() async {
        guard !hasLoaded else { return }
        do {
            let stored = try await dataStore.readValues(AppNotification.self, in: Self.notificationCollection)
            notifications = stored.values.sorted { $0.createdAt > $1.createdAt }
            hasLoaded = true
        } catch {
            // LocalDataStore exposes persistence failures through its shared error state.
        }
    }

    func recordDailyBranchCleanupCheck(
        repositoryURL: URL,
        branchNames: [String],
        now: Date = .now
    ) async {
        await load()
        let repositoryPath = repositoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let id = dailyIdentifier(repositoryPath: repositoryPath, date: now)
        let branches = Array(Set(branchNames)).sorted()

        do {
            let inserted = try await dataStore.transaction(
                reading: [Self.dailyCheckCollection, Self.notificationCollection]
            ) { transaction -> AppNotification? in
                if try transaction.value(AppNotificationDailyCheck.self, in: Self.dailyCheckCollection, id: id) != nil {
                    return nil
                }
                try transaction.set(
                    AppNotificationDailyCheck(checkedAt: now),
                    in: Self.dailyCheckCollection,
                    id: id
                )
                guard !branches.isEmpty else { return nil }
                let notification = AppNotification(
                    id: id,
                    kind: .fullyMergedBranches,
                    repositoryPath: repositoryPath,
                    branchNames: branches,
                    createdAt: now,
                    readAt: nil
                )
                try transaction.set(notification, in: Self.notificationCollection, id: id)
                return notification
            }
            if let inserted {
                notifications.removeAll { $0.id == inserted.id }
                notifications.insert(inserted, at: 0)
            }
        } catch {
            // A failed write must remain retryable on the next repository load.
        }
    }

    func activate(_ notification: AppNotification) {
        pendingBranchCleanup = notification
        guard notification.readAt == nil else { return }
        Task { await markRead(notification) }
    }

    func consumePendingBranchCleanup(id: String) {
        guard pendingBranchCleanup?.id == id else { return }
        pendingBranchCleanup = nil
    }

    private func markRead(_ notification: AppNotification) async {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }),
              notifications[index].readAt == nil else { return }
        var updated = notifications[index]
        updated.readAt = .now
        do {
            try await dataStore.transaction { transaction in
                try transaction.set(updated, in: Self.notificationCollection, id: updated.id)
            }
            guard let currentIndex = notifications.firstIndex(where: { $0.id == updated.id }) else { return }
            notifications[currentIndex] = updated
            if pendingBranchCleanup?.id == updated.id {
                pendingBranchCleanup = updated
            }
        } catch {
            // Keep the item unread when persistence fails so the action can be retried.
        }
    }

    private func dailyIdentifier(repositoryPath: String, date: Date) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "fullyMergedBranches|\(components.era ?? 0)|\(components.year ?? 0)|\(components.month ?? 0)|\(components.day ?? 0)|\(repositoryPath)"
    }
}
