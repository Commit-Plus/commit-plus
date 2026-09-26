// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct GitLFSView: View {
    let repositoryURL: URL
    let credentialResolver: @MainActor (String) async -> GitProviderCredentialResolver?
    let refreshRepository: @MainActor @Sendable () async -> Void
    @State private var controller: RepositoryLFSController
    @State private var runtime = GitLFSRuntimeController.shared
    @State private var tab = "Files"
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\GitLFSFile.name)]
    @State private var stateFilter = "All states"
    @State private var selection = Set<String>()
    @State private var pattern = ""
    @State private var literal = false
    @State private var minimumMiB = 50
    @State private var showingSetup = false
    @State private var isInitialLoadPending = true

    init(repositoryURL: URL, initialPath: String? = nil, credentialResolver: @escaping @MainActor (String) async -> GitProviderCredentialResolver?,
         refreshRepository: @escaping @MainActor @Sendable () async -> Void,
         authorizeAction: @escaping @MainActor () async -> Bool) {
        self.repositoryURL = repositoryURL
        self.credentialResolver = credentialResolver
        self.refreshRepository = refreshRepository
        _pattern = State(initialValue: initialPath ?? "")
        _literal = State(initialValue: initialPath != nil)
        _tab = State(initialValue: initialPath == nil ? "Files" : "Tracking Rules")
        _controller = State(initialValue: RepositoryLFSController(repository: repositoryURL, authorizeAction: authorizeAction))
    }

    private var files: [GitLFSFile] {
        (controller.snapshot?.files ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .filter { stateFilter == "All states" || $0.localState == stateFilter }
            .sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = controller.error ?? runtime.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
            }
            if let notice = controller.notice { Text(notice).foregroundStyle(.secondary) }
            if controller.snapshot == nil && (isInitialLoadPending || controller.isLoading) {
                ProgressView("Reading Git LFS…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if runtime.status?.activeRuntime == nil {
                ContentUnavailableView {
                    Label("Git LFS Is Required", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Download a private copy managed by Commit+, or choose System Git LFS in Settings.")
                } actions: {
                    GitLFSDownloadControls(runtime: runtime) { Task { await controller.load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let snapshot = controller.snapshot {
                if let issue = snapshot.setupIssue {
                    HStack {
                        Label(issue, systemImage: "wrench.and.screwdriver")
                        Spacer()
                        Button("Set Up Git LFS…") { showingSetup = true }
                    }
                }
                Picker("Git LFS view", selection: $tab) {
                    Text("Files").tag("Files")
                    Text("Tracking Rules").tag("Tracking Rules")
                }.pickerStyle(.segmented)
                if tab == "Files" { fileTable } else { rules(snapshot.rules) }
            } else {
                ContentUnavailableView("Unable to Read Git LFS", systemImage: "exclamationmark.triangle", description: Text("Check the message above, then Refresh to try again."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let label = controller.operationLabel {
                HStack {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading) {
                        Text(label)
                        if let progress = controller.transferProgress {
                            ProgressView(value: Double(progress.bytes), total: Double(progress.totalBytes))
                            Text("File \(progress.fileIndex) of \(progress.fileCount) · \(ByteCountFormatter.string(fromByteCount: progress.bytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)) · \(progress.name)")
                                .font(.caption).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Button("Cancel", role: .cancel) { controller.cancel() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .task {
            await controller.load(promptForRuntime: true)
            isInitialLoadPending = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)) { notification in
            guard let url = notification.object as? URL, url.standardizedFileURL == repositoryURL.standardizedFileURL else { return }
            Task { await controller.load() }
        }
        .alert("Download Git LFS?", isPresented: $controller.showingRuntimePrompt) {
            Button("Download & Continue") {
                Task { await runtime.install(); await controller.load() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Commit+ needs Git LFS to manage large files. Download a private copy on this Mac.\n\n\(runtime.downloadDescription)")
        }
        .confirmationDialog("Set up Git LFS in this repository?", isPresented: $showingSetup, titleVisibility: .visible) {
            Button("Set Up Git LFS") {
                let repository = repositoryURL
                controller.perform("Setting up Git LFS…", refresh: refreshRepository) {
                    try await GitStatusService.shared.setupLFS(in: repository)
                }
            }
        } message: {
            Text("Adds local LFS filters and the pre-push hook. Existing custom hooks are preserved. No files are staged or committed.")
        }
        .sheet(item: $controller.conversion) { review in
            VStack(alignment: .leading, spacing: 16) {
                Text("Convert to Git LFS").font(.title2)
                Text(review.path).textSelection(.enabled)
                Text("Stage this file as an LFS pointer for your next commit. The working file stays intact. Existing commits and their storage size will not change. Review and stage the tracking rule in File Status as well.")
                HStack {
                    Button("Cancel", role: .cancel) { controller.conversion = nil }
                    Spacer()
                    Button("Convert & Stage") {
                        controller.conversion = nil
                        let repository = repositoryURL
                        controller.perform("Converting selected file…", refresh: refreshRepository) {
                            try await GitStatusService.shared.convertLFS(review, in: repository)
                        }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 500)
        }
        .sheet(item: $controller.review) { review in
            VStack(alignment: .leading, spacing: 16) {
                Text(review.removing ? "Remove Tracking Rule" : "Review Tracking Rule").font(.title2)
                Text(review.pattern).font(.headline).textSelection(.enabled)
                ScrollView { Text(review.preview).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Text("Only .gitattributes will change. Review and stage it in File Status. Existing files and commit history are not converted automatically.").foregroundStyle(.secondary)
                HStack {
                    Button("Cancel", role: .cancel) { controller.review = nil }
                    Spacer()
                    Button("Apply Rule") {
                        controller.review = nil
                        let repository = repositoryURL
                        controller.perform("Updating tracking rule…", refresh: refreshRepository) {
                            try await GitStatusService.shared.applyLFSTracking(review, in: repository)
                        }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 540, height: 360)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Label("Git LFS", systemImage: "externaldrive").font(.title2)
                Text("Current branch: \(controller.snapshot?.branch ?? "—") · Remote availability is checked when downloading.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await controller.load() } }
                .disabled(controller.isLoading || controller.operationLabel != nil)
        }
    }

    private var fileTable: some View {
        @Bindable var controller = controller
        return VStack(alignment: .leading) {
            HStack {
                TextField("Search files", text: $search)
                Picker("State", selection: $stateFilter) {
                    ForEach(["All states", "Available", "Not downloaded", "Modified", "Conflict"], id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 150)
            }
            HStack {
                Picker("Remote", selection: $controller.remote) {
                    Text("Choose remote").tag("")
                    ForEach(controller.snapshot?.remotes ?? [], id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 240)
                Spacer(minLength: 12)
                Button("Download Missing", systemImage: "arrow.down.circle") { download() }
                    .disabled(controller.remote.isEmpty || controller.operationLabel != nil)
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Download Selected") { download(paths: Array(selection)) }
                        .disabled(selection.isEmpty || controller.remote.isEmpty)
                    Button("Restore Cached Content") {
                        let repository = repositoryURL
                        controller.perform("Restoring cached content…", refresh: refreshRepository) {
                            try await GitStatusService.shared.restoreLFS(in: repository)
                        }
                    }
                }.disabled(controller.operationLabel != nil)
            }
            Table(files, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("File", value: \.name)
                TableColumn("Size", value: \.size) { file in Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) }
                    .width(min: 70, ideal: 90, max: 120)
                TableColumn("Local Content", value: \.localState)
            }
            .overlay {
                if files.isEmpty {
                    ContentUnavailableView("No LFS Files", systemImage: "externaldrive", description: Text("Add a tracking rule, then stage matching files in File Status."))
                }
            }
            if selection.count == 1, let file = files.first(where: { selection.contains($0.id) }) {
                HStack {
                    Text("SHA-256: \(file.oid)").font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repositoryURL.appendingPathComponent(file.name)]) }
                }
            }
            Text("\(files.count) files · \(ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }, countStyle: .file)) referenced by this view. Local availability is not upload status.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func rules(_ rules: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Track large assets by filename or pattern. Rules are shared through .gitattributes.")
            TextField("Pattern, for example *.psd", text: $pattern)
                .disabled(controller.operationLabel != nil || controller.snapshot?.setupIssue != nil)
            HStack {
                Toggle("Exact filename", isOn: $literal)
                    .fixedSize()
                Spacer(minLength: 12)
                Button("Add…") { Task { await controller.prepareRule(pattern: pattern, literal: literal, removing: false) } }
                Button("Remove…") { Task { await controller.prepareRule(pattern: pattern, literal: literal, removing: true) } }
            }.disabled(controller.operationLabel != nil || controller.snapshot?.setupIssue != nil)
            Table(GitLFSTrackingRule.displayRules(rules)) {
                TableColumn("Pattern", value: \.pattern)
                TableColumn("Source", value: \.source)
                TableColumn("Action") { rule in
                    if rule.canRemove {
                        Button("Remove…") { Task { await controller.prepareRule(pattern: rule.pattern, literal: false, removing: true) } }
                            .disabled(controller.operationLabel != nil)
                    } else {
                        Text(rule.excluded ? "Excluded · edit source" : "Edit source file").foregroundStyle(.secondary)
                    }
                }
            }
            DisclosureGroup("Raw tracking rules") {
                ScrollView { Text(rules).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 120)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    largeFileSearchControls
                    Spacer(minLength: 16)
                    trackingFileActions
                }
                VStack(alignment: .leading, spacing: 12) {
                    largeFileSearchControls
                    trackingFileActions.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if !controller.candidates.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(controller.candidates) { candidate in
                            HStack {
                                Text(candidate.path).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: candidate.size, countStyle: .file))
                                Button("Track…") {
                                    pattern = candidate.path
                                    literal = true
                                    Task { await controller.prepareRule(pattern: candidate.path, literal: true, removing: false) }
                                }.disabled(controller.snapshot?.setupIssue != nil)
                            }
                        }
                    }
                }.frame(maxHeight: 150)
            }
            Text("Changes here apply to root rules. Edit nested or inherited rules in their source attributes file. Removing a rule does not convert existing pointers or rewrite history.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var largeFileSearchControls: some View {
        HStack {
            Stepper("Suggest files ≥ \(minimumMiB) MiB", value: $minimumMiB, in: 1...1024, step: 10)
            Button("Find Large Files") { Task { await controller.scanLargeFiles(minimumMiB: minimumMiB) } }
                .disabled(controller.isScanning)
            if controller.isScanning { ProgressView().controlSize(.small) }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var trackingFileActions: some View {
        HStack(spacing: 8) {
            Button("Convert Existing File…") {
                let panel = NSOpenPanel()
                panel.directoryURL = repositoryURL
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    let root = repositoryURL.standardizedFileURL.path + "/"
                    guard url.standardizedFileURL.path.hasPrefix(root) else {
                        controller.error = "Choose a file inside this repository."
                        return
                    }
                    let path = String(url.standardizedFileURL.path.dropFirst(root.count))
                    Task { await controller.prepareConversion(path: path) }
                }
            }.disabled(controller.operationLabel != nil || controller.snapshot?.setupIssue != nil)
            Button("Open Attributes File") { NSWorkspace.shared.open(repositoryURL.appendingPathComponent(".gitattributes")) }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func download(paths: [String]? = nil) {
        let repository = repositoryURL
        let remote = controller.remote
        Task {
            guard let resolver = await credentialResolver(remote) else { return }
            controller.perform("Downloading LFS content for the current checkout…", refresh: refreshRepository) {
                try await GitStatusService.shared.downloadLFS(remote: remote, in: repository, credentialResolver: resolver, paths: paths, onProgress: { progress in
                    Task { @MainActor in
                        if controller.operationLabel != nil { controller.transferProgress = progress }
                    }
                })
            }
        }
    }
}
