// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct GitLFSView: View {
    let repositoryURL: URL
    let initialPath: String?
    let credentialResolver: @MainActor (String) async -> GitProviderCredentialResolver?
    let refreshRepository: @MainActor @Sendable () async -> Void
    @State private var controller: RepositoryLFSController
    @State private var runtime = GitLFSRuntimeController.shared
    @State private var tab = "Files"
    @State private var search = ""
    @State private var isSearchExpanded = false
    @State private var contentWidth: CGFloat = 0
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isPatternFocused: Bool
    @State private var sortOrder = [KeyPathComparator(\GitLFSFile.name)]
    @State private var stateFilter = "All states"
    @State private var selection = Set<String>()
    @State private var pattern = ""
    @State private var literal = false
    @State private var minimumMiB = 50
    @State private var pendingRuleDeletion: GitLFSTrackingRule?
    @State private var showingSetup = false
    @State private var showingFileDetails = false
    @State private var isInitialLoadPending = true

    init(repositoryURL: URL, initialPath: String? = nil, credentialResolver: @escaping @MainActor (String) async -> GitProviderCredentialResolver?,
         refreshRepository: @escaping @MainActor @Sendable () async -> Void,
         authorizeAction: @escaping @MainActor () async -> Bool) {
        self.repositoryURL = repositoryURL
        self.initialPath = initialPath
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
                overview(snapshot)
                Picker("Git LFS view", selection: $tab) {
                    Text("Files").tag("Files")
                    Text("Tracking Rules").tag("Tracking Rules")
                }.pickerStyle(.segmented).fixedSize()
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .onChange(of: initialPath) { _, path in
            guard let path else { return }
            pattern = path
            literal = true
            tab = "Tracking Rules"
        }
        .task {
            await controller.load(promptForRuntime: true)
            isInitialLoadPending = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)) { notification in
            let url = (notification.userInfo?["repositoryURL"] as? URL) ?? (notification.object as? URL)
            guard let url, url.standardizedFileURL == repositoryURL.standardizedFileURL else { return }
            Task { await controller.load() }
        }
        .sheet(isPresented: $showingFileDetails) {
            VStack(alignment: .trailing, spacing: 12) {
                Button("Done") { showingFileDetails = false }
                fileInspector
            }.padding().frame(width: 380, height: 430)
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
        .sheet(item: $pendingRuleDeletion) { rule in
            GitLFSRemoveRuleSheet(
                rule: rule,
                onCancel: { pendingRuleDeletion = nil },
                onRemove: {
                    try await controller.removeRule(pattern: rule.pattern, refresh: refreshRepository)
                    pendingRuleDeletion = nil
                }
            )
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
                Text("Branch: \(controller.snapshot?.branch ?? "—")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Track Pattern", systemImage: "plus") { tab = "Tracking Rules" }
                .buttonStyle(.borderedProminent)
                .disabled(controller.operationLabel != nil)
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await controller.load() } }
                .disabled(controller.isLoading || controller.operationLabel != nil)
        }
    }

    private func overview(_ snapshot: GitLFSSnapshot) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: contentWidth >= 800 ? 4 : contentWidth >= 420 ? 2 : 1), spacing: 12) {
            metric("Tracked files", value: "\(snapshot.files.count)", detail: "In the current checkout", icon: "doc.on.doc")
            metric("Referenced size", value: ByteCountFormatter.string(fromByteCount: snapshot.files.reduce(0) { $0 + $1.size }, countStyle: .file), detail: "Size of tracked content", icon: "externaldrive")
            metric("Not downloaded", value: "\(snapshot.files.filter { !$0.checkout && !$0.downloaded }.count)", detail: "Content missing locally", icon: "arrow.down.circle")
            metric("Tracking rules", value: "\(GitLFSTrackingRule.displayRules(snapshot.rules).filter { !$0.excluded }.count)", detail: "From attributes files", icon: "line.3.horizontal.decrease")
        }
    }

    private func metric(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2).bold()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private var selectedFile: GitLFSFile? {
        guard selection.count == 1 else { return nil }
        return files.first { selection.contains($0.id) }
    }

    private var fileTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSearchExpanded {
                searchField
                    .onSubmit { isSearchFocused = false }
                    .onExitCommand { isSearchFocused = false }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        searchField.frame(minWidth: 180, idealWidth: 220, maxWidth: .infinity)
                        fileControls(compact: false)
                    }
                    HStack(spacing: 12) {
                        searchButton
                        Spacer(minLength: 0)
                        fileControls(compact: true)
                    }
                    HStack {
                        searchButton
                        Spacer(minLength: 0)
                        compactActions
                    }
                }
            }
            if !search.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filtering: \(search)").lineLimit(1).truncationMode(.middle)
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain).accessibilityLabel("Clear search")
                }.font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 12) {
                    fileList
                    if geometry.size.width >= 1000 { fileInspector.frame(width: 280) }
                }
            }

        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused { isSearchExpanded = false }
        }
    }

    private var searchButton: some View {
        Button {
            isSearchExpanded = true
            isSearchFocused = true
        } label: {
            Image(systemName: "magnifyingglass")
        }.accessibilityLabel("Search files").help("Search files")
    }

    private var compactActions: some View {
        Menu {
            Picker("State", selection: $stateFilter) {
                ForEach(["All states", "Available", "Not downloaded", "Cached · Restore Content", "Modified", "Conflict"], id: \.self) { Text($0).tag($0) }
            }
            remotePicker
            Divider()
            Button("Download Missing") { download() }
                .disabled(controller.remote.isEmpty || controller.operationLabel != nil)
            Button("Download Selected") { download(paths: Array(selection)) }
                .disabled(selection.isEmpty || controller.remote.isEmpty || controller.operationLabel != nil)
            Button("Restore Cached Content") { restoreCachedContent() }
                .disabled(controller.operationLabel != nil)
            Button("File Details") { showingFileDetails = true }
                .disabled(selectedFile == nil)
        } label: {
            Image(systemName: "ellipsis.circle")
        }.accessibilityLabel("Filters and file actions")
    }

    private var searchField: some View {
        TextField("Search files", text: $search)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
    }

    private func fileControls(compact: Bool) -> some View {
        @Bindable var controller = controller
        return HStack(spacing: 12) {
            Picker("State", selection: $stateFilter) {
                ForEach(["All states", "Available", "Not downloaded", "Cached · Restore Content", "Modified", "Conflict"], id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: compact ? 135 : 155)
            VStack(spacing: 0) {
                if compact {
                    remotePicker.labelsHidden()
                } else {
                    remotePicker
                }
            }.fixedSize()
            Button { download() } label: {
                if compact {
                    Image(systemName: "arrow.down.circle")
                } else {
                    Label("Download Missing", systemImage: "arrow.down.circle")
                }
            }
            .accessibilityLabel("Download Missing")
            .help("Download missing Git LFS content")
            .disabled(controller.remote.isEmpty || controller.operationLabel != nil)
            Menu {
                Button("File Details") { showingFileDetails = true }
                    .disabled(selectedFile == nil)
                Button("Download Selected") { download(paths: Array(selection)) }
                    .disabled(selection.isEmpty || controller.remote.isEmpty)
                Button("Restore Cached Content") { restoreCachedContent() }
            } label: {
                if compact { Image(systemName: "ellipsis.circle") }
                else { Label("More", systemImage: "ellipsis.circle") }
            }.accessibilityLabel("More file actions").disabled(controller.operationLabel != nil)
        }.fixedSize()
    }

    private var remotePicker: some View {
        @Bindable var controller = controller
        return Picker("Download from", selection: $controller.remote) {
            if controller.remote.isEmpty { Text("No download remote").tag("") }
            ForEach(controller.snapshot?.remotes ?? [], id: \.self) { Text($0).tag($0) }
        }.help("Remote used to download Git LFS content. This does not change file tracking.")
    }

    private var fileList: some View {
        Table(files, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("File", value: \.name) { file in
                HStack(spacing: 8) {
                    Image(systemName: "doc").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(URL(fileURLWithPath: file.name).lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text((file.name as NSString).deletingLastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }.padding(.vertical, 4)
                }
            }.width(min: 180, ideal: 210, max: 240)
            TableColumn("Size", value: \.size) { file in
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).monospacedDigit()
            }.width(min: 65, ideal: 80, max: 85)
            TableColumn("Local Content", value: \.localState) { file in
                fileState(file)
            }.width(min: 100, ideal: 110, max: 120)
            TableColumn("Author") { file in Text(file.lastAuthor ?? "—").lineLimit(1) }
                .width(min: 80, ideal: 95, max: 100)
            TableColumn("Last Commit") { file in Text(commitDate(file)).font(.caption) }
                .width(min: 85, ideal: 90, max: 95)
            TableColumn("OID") { file in Text(String(file.oid.prefix(10))).font(.system(.caption, design: .monospaced)).help(file.oid) }
                .width(min: 85, ideal: 85, max: 90)
        }
        .overlay {
            if files.isEmpty {
                ContentUnavailableView("No LFS Files", systemImage: "externaldrive", description: Text(search.isEmpty && stateFilter == "All states" ? "Add a tracking rule, then stage matching files in File Status." : "Try another search or state filter."))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private func fileState(_ file: GitLFSFile) -> some View {
        let color: Color = file.modification != nil ? .orange : file.checkout ? .green : .secondary
        return Label(file.localState, systemImage: file.modification != nil ? "exclamationmark.circle" : file.checkout ? "checkmark.circle.fill" : "arrow.down.circle")
            .font(.caption).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }

    private var fileInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let file = selectedFile {
                    Label(URL(fileURLWithPath: file.name).lastPathComponent, systemImage: "doc")
                        .font(.headline).textSelection(.enabled)
                    Text(file.name).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    fileState(file)
                    Divider()
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    LabeledContent("Local cache", value: file.downloaded ? "Available" : "Missing")
                    LabeledContent("Last author", value: file.lastAuthor ?? "—")
                    LabeledContent("Last commit", value: commitDate(file))
                    if file.lastCommitDate == nil {
                        Text("No commit metadata found in the latest 500 commits.").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Object ID · SHA-256").font(.caption).foregroundStyle(.secondary)
                        Text(file.oid).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    Text("Remote availability is checked when downloading.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    VStack(spacing: 8) {
                        Button { reveal(file) } label: {
                            Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity)
                        }
                        Button { download(paths: [file.name]) } label: {
                            Label("Download Selected", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                        }
                        .disabled(controller.remote.isEmpty || controller.operationLabel != nil)
                    }.buttonStyle(.bordered).controlSize(.regular)

                } else {
                    ContentUnavailableView(selection.isEmpty ? "File Details" : "\(selection.count) Files Selected", systemImage: "doc.text.magnifyingglass", description: Text("Select one file to inspect its content and object ID."))
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private func commitDate(_ file: GitLFSFile) -> String {
        guard let value = file.lastCommitDate, let date = ISO8601DateFormatter().date(from: value) else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func reveal(_ file: GitLFSFile) {
        NSWorkspace.shared.activateFileViewerSelecting([repositoryURL.appendingPathComponent(file.name)])
    }

    private func restoreCachedContent() {
        let repository = repositoryURL
        controller.perform("Restoring cached content…", refresh: refreshRepository) {
            try await GitStatusService.shared.restoreLFS(in: repository)
        }
    }

    private func rules(_ rules: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tracking Rules").font(.headline)
                Text("Choose which files Git LFS should track. Rules are shared through .gitattributes.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField("Pattern, for example *.mp4", text: $pattern)
                    .textFieldStyle(.plain)
                    .focused($isPatternFocused)
                if !pattern.isEmpty {
                    Button { pattern = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear pattern")
                    .help("Clear input")
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isPatternFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isPatternFocused ? 2 : 1))
            .disabled(controller.operationLabel != nil || controller.snapshot?.setupIssue != nil)
            HStack {
                Toggle("Match exact filename", isOn: $literal)
                    .fixedSize()
                Spacer(minLength: 12)
                Button("Add Pattern…", systemImage: "plus") {
                    Task { await controller.prepareRule(pattern: pattern, literal: literal, removing: false) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pattern.isEmpty)
            }.disabled(controller.operationLabel != nil || controller.snapshot?.setupIssue != nil)
            Text(literal
                 ? "Matches one filename exactly, for example video.mp4. Wildcards such as * are treated as part of the filename."
                 : "Matches a filename or wildcard pattern. For example, *.mp4 tracks all MP4 files.")
                .font(.caption).foregroundStyle(.secondary)
            Table(GitLFSTrackingRule.displayRules(rules)) {
                TableColumn("Pattern") { rule in
                    Text(rule.pattern).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }.width(min: 160, ideal: 280)
                TableColumn("Type", value: \.patternKind)
                    .width(min: 65, ideal: 80, max: 95)
                TableColumn("Source", value: \.source)
                TableColumn("Status") { rule in
                    Text(rule.excluded ? "Excluded" : "Tracked")
                        .font(.caption)
                        .foregroundStyle(rule.excluded ? Color.orange : Color.green)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((rule.excluded ? Color.orange : Color.green).opacity(0.1), in: Capsule())
                }.width(min: 75, ideal: 90, max: 100)
                TableColumn("Action") { rule in
                    if rule.canRemove {
                        Button {
                            pendingRuleDeletion = rule
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(rule.pattern)")
                        .help("Remove this tracking rule")
                        .disabled(controller.operationLabel != nil)
                    } else {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                            .help("Edit this rule in \(rule.source)")
                            .accessibilityLabel("Edit source file: \(rule.source)")
                    }
                }.width(50)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            Text("Pattern uses wildcards; Filename matches a literal name. Tracked describes the rule, not upload status.")
                .font(.caption).foregroundStyle(.secondary)
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
