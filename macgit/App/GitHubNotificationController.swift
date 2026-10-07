// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Combine
import Foundation

@MainActor
final class GitHubNotificationController: ObservableObject {
    @Published private(set) var accounts: [GitProviderAccount] = []
    @Published private(set) var caches: [String: GitHubNotificationCache] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var busyAccounts: Set<String> = []
    @Published var selectedAccountKey: String {
        didSet { defaults.set(selectedAccountKey, forKey: "githubNotifications.selectedAccount") }
    }
    private let dataStore: LocalDataStore
    private let tokenVault: any GitProviderTokenVault
    private let service: any GitHubNotificationProviding
    private let defaults: UserDefaults
    private var subscription: AnyCancellable?
    private var polling: Task<Void, Never>?
    private var reconciliation: Task<Void, Never>?
    private var viewTasks: [String: Task<Void, Never>] = [:]
    private let openURL: (URL) -> Bool
    private var operations: [String: Task<Void, Never>] = [:]
    private var generations: [String: UUID] = [:]
    private let collection = "githubNotificationCache"

    init(tokenVault: any GitProviderTokenVault, dataStore: LocalDataStore? = nil,
         service: (any GitHubNotificationProviding)? = nil, defaults: UserDefaults = .standard,
         openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.tokenVault = tokenVault
        self.dataStore = dataStore ?? .shared
        self.service = service ?? GitHubNotificationService()
        self.defaults = defaults
        self.openURL = openURL
        selectedAccountKey = defaults.string(forKey: "githubNotifications.selectedAccount") ?? ""
    }

    func start(provider: GitProviderAccountController) {
        guard subscription == nil else { return }
        subscription = provider.$accounts.combineLatest(provider.$isLoading)
            .filter { !$0.1 }
            .map(\.0)
            .removeDuplicates()
            .sink { [weak self] accounts in self?.acceptAccounts(accounts) }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self else { return }
                self.refreshAllIfNeeded()
            }
        }
    }

    var selectedAccounts: [GitProviderAccount] {
        selectedAccountKey == "all" ? accounts : accounts.filter { key($0) == selectedAccountKey }
    }
    var isRefreshing: Bool { selectedAccounts.contains { busyAccounts.contains(key($0)) } }
    var unreadCount: Int { accounts.reduce(0) { $0 + unreadCount(for: $1) } }
    func unreadCount(for account: GitProviderAccount) -> Int { caches[key(account)]?.notifications.filter(\.unread).count ?? 0 }
    func key(_ account: GitProviderAccount) -> String { GitHubNotificationCache.key(for: account) }

    func acceptAccounts(_ values: [GitProviderAccount]) {
        let values = values.filter { $0.provider == .github }
        let oldKeys = Set(accounts.map(key))
        let newKeys = Set(values.map(key))
        let removed = oldKeys.subtracting(newKeys)
        for id in removed {
            for taskID in viewTasks.keys.filter({ $0.hasPrefix(id + ":") }) {
                viewTasks.removeValue(forKey: taskID)?.cancel()
            }
            generations[id] = nil
            operations.removeValue(forKey: id)?.cancel()
            caches[id] = nil
            errors[id] = nil
            busyAccounts.remove(id)
        }
        for account in values {
            let id = key(account)
            if let previous = accounts.first(where: { key($0) == id }), previous != account, errors[id] != nil {
                caches[id]?.retryAt = nil
                caches[id]?.nextFetchAt = nil
                caches[id]?.refreshedAt = nil
                errors[id] = nil
            }
        }
        accounts = values
        // Account restoration starts with an empty list. Preserve the saved filter
        // until actual accounts arrive rather than overwriting it during startup.
        if !values.isEmpty, selectedAccountKey != "all", !newKeys.contains(selectedAccountKey) {
            selectedAccountKey = values.first.map(key) ?? ""
        }
        let previous = reconciliation
        reconciliation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                // Delete only accounts explicitly removed from the loaded list;
                // an initial empty account list must not purge persistent caches.
                try await self.dataStore.transaction { transaction in
                    for id in removed { transaction.remove(in: self.collection, id: id) }
                }
                for account in values {
                    let id = self.key(account)
                    guard self.accounts.contains(account), self.caches[id] == nil else { continue }
                    let cache = try await self.dataStore.readValue(GitHubNotificationCache.self, in: self.collection, id: id)
                    guard self.accounts.contains(account) else { continue }
                    self.caches[id] = cache ?? GitHubNotificationCache()
                }
                self.refreshAllIfNeeded()
            } catch {
                for account in values where self.accounts.contains(account) {
                    self.errors[self.key(account)] = "Could not load notification cache: \(error.localizedDescription)"
                }
            }
        }
    }

    func opened() { refreshSelected(force: false) }
    func refreshSelected(force: Bool = true) {
        for account in selectedAccounts { refresh(account, force: force) }
    }
    private func refreshAllIfNeeded() {
        for account in accounts {
            let id = key(account)
            if let cache = caches[id], cache.retryAt.map({ $0 <= .now }) ?? true,
               let pending = cache.pendingReads?.first,
               let notification = cache.notifications.first(where: { $0.id == pending.key }) {
                update(notification, account: account, done: false)
            } else {
                refresh(account, force: false)
            }
        }
    }

    private func token(for account: GitProviderAccount) throws -> GitProviderToken {
        guard account.tokenStatus == .valid,
              let token = try tokenVault.readToken(for: account),
              token.expiresAt.map({ $0 > .now }) ?? true else {
            throw GitHubNotificationError(message: "Connect a compatible GitHub API token on this Mac to view notifications. SSH credentials alone cannot fetch the inbox.", retryAt: .now.addingTimeInterval(300))
        }
        return token
    }

    private func refresh(_ account: GitProviderAccount, force: Bool) {
        let id = key(account)
        guard let cache = caches[id], !busyAccounts.contains(id) else { return }
        let now = Date.now
        // Manual refresh skips cache freshness, but never skips server backoff.
        guard cache.nextFetchAt.map({ $0 <= now }) ?? true,
              cache.retryAt.map({ $0 <= now }) ?? true else { return }
        if !force, let date = cache.refreshedAt, now.timeIntervalSince(date) < 60 { return }
        let generation = UUID()
        generations[id] = generation
        busyAccounts.insert(id)
        operations[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.finish(id, generation: generation) }
            do {
                let result = try await self.service.fetch(account: account, token: self.token(for: account), lastModified: cache.lastModified)
                guard self.isCurrent(id, generation: generation) else { return }
                var next = cache
                if let notifications = result.notifications { next.replace(with: notifications) }
                // Preserve views made while the fetch was in flight. A later update
                // on the same thread is a new unread notification.
                next.pendingReads = self.caches[id]?.pendingReads
                for index in next.notifications.indices {
                    let item = next.notifications[index]
                    if let viewedAt = next.pendingReads?[item.id] {
                        if item.updatedAt <= viewedAt { next.notifications[index].unread = false }
                        else { next.pendingReads?[item.id] = nil }
                    }
                }
                next.retryAt = nil
                next.lastModified = result.lastModified
                next.refreshedAt = .now
                // X-Poll-Interval is a server restriction, separate from freshness.
                next.nextFetchAt = .now.addingTimeInterval(result.pollInterval)
                try await self.save(next, id: id, generation: generation)
                guard self.isCurrent(id, generation: generation) else { return }
                self.caches[id] = next
                self.errors[id] = nil
            } catch {
                await self.record(error, id: id, generation: generation)
            }
        }
    }

    func update(_ notification: GitHubNotification, account: GitProviderAccount, done: Bool) {
        let id = key(account)
        guard accounts.contains(account), !busyAccounts.contains(id) else { return }
        let generation = UUID()
        generations[id] = generation
        busyAccounts.insert(id)
        operations[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.finish(id, generation: generation) }
            do {
                guard self.caches[id]?.retryAt.map({ $0 <= .now }) ?? true else { return }
                try await self.service.update(threadID: notification.id, done: done, account: account, token: self.token(for: account))
                guard self.isCurrent(id, generation: generation), var cache = self.caches[id] else { return }
                if done { cache.notifications.removeAll { $0.id == notification.id } }
                else if let index = cache.notifications.firstIndex(where: { $0.id == notification.id }) {
                    cache.notifications[index].unread = false
                    cache.pendingReads?[notification.id] = nil
                }
                // Local mutation invalidates the cached conditional response.
                cache.lastModified = nil
                self.caches[id] = cache
                try await self.save(cache, id: id, generation: generation)
                guard self.isCurrent(id, generation: generation) else { return }
                self.errors[id] = nil
            } catch { await self.record(error, id: id, generation: generation) }
        }
    }

    func open(_ notification: GitHubNotification, account: GitProviderAccount) {
        guard accounts.contains(account), openURL(notification.webURL(account: account)) else { return }
        let id = key(account)
        guard var cache = caches[id], let index = cache.notifications.firstIndex(where: { $0.id == notification.id }),
              cache.notifications[index].unread else { return }
        cache.notifications[index].unread = false
        if cache.pendingReads == nil { cache.pendingReads = [:] }
        cache.pendingReads?[notification.id] = cache.notifications[index].updatedAt
        cache.lastModified = nil
        caches[id] = cache
        let taskID = id + ":" + notification.id
        guard viewTasks[taskID] == nil else { return }
        let previous = operations[id]
        viewTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            defer { self.viewTasks[taskID] = nil }
            await previous?.value
            guard !Task.isCancelled, self.accounts.contains(account), var current = self.caches[id],
                  let index = current.notifications.firstIndex(where: { $0.id == notification.id }),
                  current.notifications[index].updatedAt <= notification.updatedAt else { return }
            // Reapply after an in-flight fetch, then persist before the API call.
            current.notifications[index].unread = false
            if current.pendingReads == nil { current.pendingReads = [:] }
            current.pendingReads?[notification.id] = notification.updatedAt
            current.lastModified = nil
            self.caches[id] = current
            do {
                try await self.dataStore.transaction { transaction in
                    guard self.accounts.contains(account), let latest = self.caches[id] else { return }
                    try transaction.set(latest, in: self.collection, id: id)
                }
                self.update(notification, account: account, done: false)
            } catch { self.errors[id] = "Could not save viewed notification: \(error.localizedDescription)" }
        }
    }
    func openInbox(account: GitProviderAccount) { NSWorkspace.shared.open(account.hostURL.appending(path: "notifications")) }

    private func save(_ cache: GitHubNotificationCache, id: String, generation: UUID) async throws {
        try await dataStore.transaction { transaction in
            guard self.generations[id] == generation,
                  self.accounts.contains(where: { self.key($0) == id }) else { return }
            try transaction.set(cache, in: self.collection, id: id)
        }
    }
    private func isCurrent(_ id: String, generation: UUID) -> Bool {
        !Task.isCancelled && generations[id] == generation && accounts.contains { key($0) == id }
    }
    private func finish(_ id: String, generation: UUID) {
        guard generations[id] == generation else { return }
        busyAccounts.remove(id)
        operations[id] = nil
    }
    private func record(_ error: Error, id: String, generation: UUID) async {
        guard isCurrent(id, generation: generation) else { return }
        errors[id] = error.localizedDescription
        var cache = caches[id] ?? GitHubNotificationCache()
        cache.retryAt = (error as? GitHubNotificationError)?.retryAt ?? .now.addingTimeInterval(60)
        caches[id] = cache
        try? await save(cache, id: id, generation: generation)
    }
}
