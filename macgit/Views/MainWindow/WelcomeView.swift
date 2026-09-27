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
import SwiftUI

struct WelcomeView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var bookmarkController: RepositoryBookmarkController
    @State private var locationError: String?
    @ObservedObject private var store = RecentRepositoriesStore.shared
    @State private var model = WelcomeDashboardModel()
    @State private var showingUnavailableRepository = false
    @State private var hasStartedLoading = false
    @State private var refreshID = UUID()
    let accountDisplayName: String?
    let onOpenAccount: () -> Void
    let onRepositoryOpened: (URL) -> Void

    var body: some View {
        PersistentHSplit(
            autosaveName: "WelcomeDashboardMainSplit",
            left: {
                RepoPickerView(isDashboardSidebar: true, onRepositoryOpened: onRepositoryOpened)
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 600)
            },
            right: {
                WelcomeDashboardContent(
                    model: model, accountDisplayName: accountDisplayName, repositoryCount: store.repositories.count,
                    onRefresh: refreshImmediately, onOpenAccount: onOpenAccount,
                    onReviewAttention: reviewAttention, onRepositoryOpened: openRepository
                )
                .frame(minWidth: 560)
            }
        )
        .frame(minWidth: 900, minHeight: 620)
        .alert("Repository Unavailable", isPresented: $showingUnavailableRepository) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(locationError ?? "Use the repository list to locate its folder or remove it from recents.")
        }
        .task(id: refreshID) {
            // The first render uses disk cache immediately. Subsequent events
            // share a short cancellable debounce instead of starting Git scans.
            if hasStartedLoading {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
            hasStartedLoading = true
            async let activity: Void = model.refresh(repositories: store.repositories)
            async let attention: Void = model.refreshAttention(repositories: store.repositories)
            _ = await (activity, attention)
        }
        .onChange(of: store.repositories.map { "\($0.url.path)|\($0.lastOpened.timeIntervalSince1970)" }) { _, _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.invalidate(repositories: store.repositories, activity: false)
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshImmediately() }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange), perform: refreshRepository)
        .onReceive(NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh), perform: refreshRepository)
    }

    private func reviewAttention(_ repository: WelcomeRepositoryAttention) {
        if repository.unavailable {
            locateRepository(repository)
            return
        }
        guard FileManager.default.fileExists(atPath: repository.url.appendingPathComponent(".git").path) else {
            locateRepository(repository)
            return
        }
        store.add(repository.url)
        openWindow(id: "main", value: RepositoryWindowRequest.repository(
            repository.url, shouldFitVisibleScreen: true, showsHistory: repository.showsHistory
        ))
    }

    private func locateRepository(_ repository: WelcomeRepositoryAttention) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the new location for \(repository.name)"
        panel.prompt = "Use Folder"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else {
                        throw CocoaError(.fileReadInvalidFileName)
                    }
                    if let id = bookmarkController.bookmarkID(linkedTo: repository.url),
                       let bookmark = bookmarkController.bookmark(forID: id) {
                        try await bookmarkController.validateAndLink(bookmark, to: url)
                    }
                    if let old = store.repositories.first(where: { $0.url == repository.url }) {
                        store.remove(old)
                    }
                    store.add(url)
                    onRepositoryOpened(url)
                } catch {
                    locationError = "Could not use this repository folder. \(error.localizedDescription)"
                    showingUnavailableRepository = true
                }
            }
        }
    }

    private func refreshImmediately() {
        model.invalidate(repositories: store.repositories)
        refresh()
    }

    private func refreshRepository(_ notification: Notification) {
        if let url = notification.userInfo?["repositoryURL"] as? URL {
            let repositories = store.repositories.filter { $0.url.standardizedFileURL == url.standardizedFileURL }
            guard !repositories.isEmpty else { return }
            model.invalidate(repositories: repositories)
        } else {
            model.invalidate(repositories: store.repositories)
        }
        refresh()
    }

    private func refresh() { refreshID = UUID() }

    private func openRepository(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else {
            showingUnavailableRepository = true
            refresh()
            return
        }
        store.add(url)
        onRepositoryOpened(url)
    }
}
