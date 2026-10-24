// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

@MainActor
final class AppNotificationController: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var pendingBranchCleanup: AppNotification?
    @Published private(set) var pendingPullRequest: AppNotification?

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

    func recordPullRequestCreated(
        _ pullRequest: PullRequestSummary,
        repositoryURL: URL,
        remoteName: String?,
        now: Date = .now
    ) async {
        await load()
        let repositoryPath = repositoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let notification = AppNotification(
            id: "pullRequestCreated|\(pullRequest.webURL.absoluteString)",
            kind: .pullRequestCreated,
            repositoryPath: repositoryPath,
            branchNames: [pullRequest.source.ref],
            createdAt: now,
            readAt: nil,
            pullRequest: pullRequest,
            remoteName: remoteName
        )
        do {
            try await dataStore.transaction { transaction in
                try transaction.set(notification, in: Self.notificationCollection, id: notification.id)
            }
            notifications.removeAll { $0.id == notification.id }
            notifications.insert(notification, at: 0)
        } catch {
            // The system notification already reported the result; the in-app entry is supplemental.
        }
    }

    func activate(_ notification: AppNotification) {
        switch notification.kind {
        case .fullyMergedBranches:
            pendingBranchCleanup = notification
        case .pullRequestCreated:
            pendingPullRequest = notification
        }
        guard notification.readAt == nil else { return }
        Task { await markRead(notification) }
    }

    /// Unread notifications shown as window banners for a repository, newest first.
    /// Only the newest notification of each kind is kept: older daily checks are superseded.
    func bannerNotifications(for repositoryURL: URL) -> [AppNotification] {
        let repositoryPath = repositoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        var seenKinds: Set<AppNotification.Kind> = []
        return notifications.filter {
            $0.kind == .fullyMergedBranches && $0.readAt == nil && $0.repositoryPath == repositoryPath
                && seenKinds.insert($0.kind).inserted
        }
    }

    func dismiss(_ notification: AppNotification) {
        Task { await markRead(notification) }
    }

    func consumePendingBranchCleanup(id: String) {
        guard pendingBranchCleanup?.id == id else { return }
        pendingBranchCleanup = nil
    }

    func consumePendingPullRequest(id: String) {
        guard pendingPullRequest?.id == id else { return }
        pendingPullRequest = nil
    }

    func delete(_ notification: AppNotification) async {
        await delete(ids: [notification.id])
    }

    func deleteAll() async {
        await delete(ids: notifications.map(\.id))
    }

    private func delete(ids: [String]) async {
        guard !ids.isEmpty else { return }
        do {
            try await dataStore.transaction { transaction in
                for id in ids {
                    transaction.remove(in: Self.notificationCollection, id: id)
                }
            }
            notifications.removeAll { ids.contains($0.id) }
            if let pendingBranchCleanup, ids.contains(pendingBranchCleanup.id) {
                self.pendingBranchCleanup = nil
            }
            if let pendingPullRequest, ids.contains(pendingPullRequest.id) {
                self.pendingPullRequest = nil
            }
        } catch {
            // Keep the notifications visible when persistence fails so deletion can be retried.
        }
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
            if pendingPullRequest?.id == updated.id {
                pendingPullRequest = updated
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
