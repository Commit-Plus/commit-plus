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
import Foundation
import Observation

@MainActor
@Observable
final class WelcomeDashboardModel {
    private(set) var snapshot = WelcomeDashboardSnapshot(days: WelcomeDashboardSnapshot.days(endingAt: .now))
    private(set) var isLoading = true
    private(set) var updatedAt: Date?
    private(set) var attention: [WelcomeRepositoryAttention] = []
    private(set) var isCheckingAttention = true
    private(set) var attentionUpdatedAt: Date?
    private var attentionGeneration = UUID()
    private var generation = UUID()
    private var dirtyActivityURLs: Set<URL> = []
    private var checkedAttentionURLs: Set<URL> = []
    private let activityCache: WelcomeActivityCache
    private let activityLoader: (RecentRepository, [Date]) async throws -> WelcomeRepositoryActivity
    private let attentionLoader: (RecentRepository) async throws -> WelcomeRepositoryAttention

    init(
        activityCache: WelcomeActivityCache = .shared,
        activityLoader: @escaping (RecentRepository, [Date]) async throws -> WelcomeRepositoryActivity = {
            try await GitStatusService.shared.welcomeActivity(for: $0, days: $1)
        },
        attentionLoader: @escaping (RecentRepository) async throws -> WelcomeRepositoryAttention = {
            try await GitStatusService.shared.welcomeAttention(for: $0)
        }
    ) {
        self.activityCache = activityCache
        self.activityLoader = activityLoader
        self.attentionLoader = attentionLoader
    }

    /// Keep invalidations until a successful read, including across cancelled refreshes.
    func invalidate(repositories: [RecentRepository], activity: Bool = true) {
        let urls = Set(repositories.map { $0.url.standardizedFileURL })
        if activity { dirtyActivityURLs.formUnion(urls) }
        checkedAttentionURLs.subtract(urls)
        generation = UUID()
        attentionGeneration = UUID()
    }

    func refreshAttention(repositories: [RecentRepository]) async {
        let request = UUID()
        attentionGeneration = request
        isCheckingAttention = true
        let recent = uniqueRepositories(repositories)
        let urls = Set(recent.map { $0.url.standardizedFileURL })
        checkedAttentionURLs.formIntersection(urls)
        attention.removeAll { !urls.contains($0.url.standardizedFileURL) }
        for repository in recent {
            guard !Task.isCancelled, request == attentionGeneration else { return }
            let url = repository.url.standardizedFileURL
            guard !checkedAttentionURLs.contains(url) else { continue }
            do {
                let status = try await attentionLoader(repository)
                guard !Task.isCancelled, request == attentionGeneration else { return }
                attention.removeAll { $0.url.standardizedFileURL == url }
                if status.needsAttention { attention.append(status) }
                attention.sort {
                    if $0.priority != $1.priority { return $0.priority < $1.priority }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                checkedAttentionURLs.insert(url)
            } catch {
                guard !Task.isCancelled, request == attentionGeneration else { return }
                // Preserve the previous warning and retry on the next refresh.
            }
        }
        guard !Task.isCancelled, request == attentionGeneration else { return }
        attentionUpdatedAt = .now
        isCheckingAttention = false
    }

    func refresh(repositories: [RecentRepository], force: Bool = false) async {
        let request = UUID()
        generation = request
        isLoading = true
        let now = Date.now
        let days = WelcomeDashboardSnapshot.days(endingAt: now)
        let all = uniqueRepositories(repositories)
        dirtyActivityURLs.formIntersection(Set(all.map { $0.url.standardizedFileURL }))
        let recent = Array(all.prefix(7))
        if force { dirtyActivityURLs.formUnion(recent.map { $0.url.standardizedFileURL }) }
        var entries: [URL: WelcomeActivityCacheEntry] = [:]
        var pending: [RecentRepository] = []

        // Read every visible cached row before starting any Git command, so a
        // slow cache miss cannot hold back the other repositories' activity.
        for repository in recent {
            let url = repository.url.standardizedFileURL
            let cached = await activityCache.entry(for: url, days: days, now: now)
            guard !Task.isCancelled, request == generation else { return }
            if let cached { entries[url] = cached }
            if cached == nil || dirtyActivityURLs.contains(url) { pending.append(repository) }
        }
        publishActivity(entries, repositories: recent, days: days)
        for repository in pending {
            guard !Task.isCancelled, request == generation else { return }
            do {
                let activity = try await activityLoader(repository, days)
                guard !Task.isCancelled, request == generation else { return }
                let entry = WelcomeActivityCacheEntry(days: days, savedAt: .now, activity: activity)
                await activityCache.save(entry)
                guard !Task.isCancelled, request == generation else { return }
                let url = repository.url.standardizedFileURL
                dirtyActivityURLs.remove(url)
                entries[url] = entry
                publishActivity(entries, repositories: recent, days: days)
            } catch {
                guard !Task.isCancelled, request == generation else { return }
            }
        }
        guard !Task.isCancelled, request == generation else { return }
        isLoading = false
    }

    private func publishActivity(
        _ entries: [URL: WelcomeActivityCacheEntry],
        repositories: [RecentRepository],
        days: [Date]
    ) {
        var result = WelcomeDashboardSnapshot(days: days)
        let ordered = repositories.compactMap { entries[$0.url.standardizedFileURL] }
        result.repositories = ordered.map(\.activity)
        snapshot = result
        updatedAt = ordered.map(\.savedAt).min()
    }

    private func uniqueRepositories(_ repositories: [RecentRepository]) -> [RecentRepository] {
        var seen = Set<URL>()
        return repositories.sorted { $0.lastOpened > $1.lastOpened }
            .filter { seen.insert($0.url.standardizedFileURL).inserted }
    }
}
