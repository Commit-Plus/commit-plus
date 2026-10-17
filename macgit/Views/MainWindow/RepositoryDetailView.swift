// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryDetailView: View {
    let repositoryURL: URL
    let onClose: (() -> Void)?
    let onOpen: (URL) -> Void
    let isActive: Bool
    @EnvironmentObject private var appState: AppState
    @State private var fileOpener = RepositoryFileOpenModel()
    // Welcome owns these models across repository selections; standalone
    // previews keep their own model for the lifetime of this view.
    @State private var model: RepositoryDetailModel
    @State private var tab: RepositoryDetailTab = .summary
    @State private var refresh = 0

    init(repositoryURL: URL, onClose: (() -> Void)?, onOpen: @escaping (URL) -> Void,
         model: RepositoryDetailModel? = nil, isActive: Bool = true) {
        self.repositoryURL = repositoryURL
        self.onClose = onClose
        self.onOpen = onOpen
        self.isActive = isActive
        _model = State(initialValue: model ?? RepositoryDetailModel())
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    RepositoryDetailHeader(repositoryURL: repositoryURL, onClose: onClose,
                                           onRefresh: { refresh += 1 }, onOpen: { onOpen(repositoryURL) })
                    Divider()
                    RepositoryOverviewSection(info: model.info, size: model.size, isLoading: model.isLoading, error: model.error)
                        .padding(20)
                    Color.clear.frame(height: 1).id("repository-detail-content-start")
                    Section {
                        switch tab {
                        case .summary:
                            RepositoryReadmeSection(repositoryURL: repositoryURL, content: model.readme, file: model.readmeURL, isLoading: model.isLoading,
                                                    onOpenFile: { fileOpener.prepare($0, appState: appState) })
                        case .statistics:
                            RepositoryStatisticsView(repositoryURL: repositoryURL, isActive: isActive)
                                .padding(20)
                        }
                    } header: {
                        VStack(spacing: 0) {
                            HStack {
                                Picker("Repository details", selection: $tab) {
                                    Text("Summary").tag(RepositoryDetailTab.summary)
                                    Text("Statistics").tag(RepositoryDetailTab.statistics)
                                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                                Spacer()
                            }.padding(.horizontal, 20).padding(.vertical, 12)
                            Divider()
                        }
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
            }
            .onChange(of: tab) {
                // Reset the shared offset when changing between documents of
                // different heights; keep the tabs pinned above the new content.
                scrollProxy.scrollTo("repository-detail-content-start", anchor: .top)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $fileOpener.request) { request in
            SearchFileOpenSheet(request: request) { application, remember in
                fileOpener.choose(application, remember: remember, appState: appState)
            }
        }
        .alert("Could Not Open File", isPresented: Binding(get: { fileOpener.error != nil }, set: { if !$0 { fileOpener.error = nil } })) {
            Button("OK", role: .cancel) { fileOpener.error = nil }
        } message: {
            Text(fileOpener.error ?? "")
        }
        .task(id: "\(repositoryURL.path)|\(refresh)|\(isActive)") {
            guard isActive else { return }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await model.load(repositoryURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if isActive { refresh += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in repositoryChanged(notification) }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)) { notification in repositoryChanged(notification) }
    }

    private func repositoryChanged(_ notification: Notification) {
        guard isActive else { return }
        if let url = notification.userInfo?["repositoryURL"] as? URL, url.standardizedFileURL != repositoryURL.standardizedFileURL { return }
        refresh += 1
    }
}
