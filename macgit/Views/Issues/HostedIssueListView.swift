// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// The repository's GitHub, GitLab, Bitbucket, or Azure Boards issues.
struct HostedIssueListView: View {
    @Environment(\.appTextScale) private var textScale
    @ObservedObject var controller: HostedIssueController
    /// The screen stays mounted while hidden, so loading follows visibility rather than appearance.
    let isActive: Bool
    let canManageGitHubOrganizationAccess: Bool
    let onOpenAccounts: () -> Void
    let onOpenGitHubOrganizationAccess: () -> Void
    let gitFlowEnabled: Bool
    let onCreateBranch: (String, String, IssueBranchTarget) -> Void
    @State private var isCreatingIssue = false
    @AppStorage("hostedIssues.detailPanelWidth") private var storedDetailPanelWidth = Double(HostedIssueDetailView.defaultWidth)

    private static let issueListMinimumWidth: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if controller.accountProblem == nil, controller.selectedRemote != nil {
                filterBar
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: isActive) {
            if isActive {
                await controller.activate()
            } else {
                controller.deactivate()
            }
        }
        .sheet(isPresented: $isCreatingIssue) {
            NewHostedIssueSheet(controller: controller)
        }
    }

    private var provider: HostedIssueProvider? { controller.provider }

    // MARK: - Header and filters

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(provider?.sidebarTitle ?? "Issues")
                    .font(.headline.scaled(by: textScale))
                if let remote = controller.selectedRemote {
                    Text(subtitle(for: remote))
                        .font(.caption.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if controller.accountProblem == nil, controller.selectedRemote != nil {
                TextField("Search title or number", text: $controller.searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.scaled(by: textScale))
                    .frame(width: 220 * textScale)
                if controller.isLoading, controller.hasLoadedList {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh Issues", systemImage: "arrow.clockwise", action: controller.refresh)
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .disabled(controller.isLoading)
                    .help("Refresh")
                Button("New Issue…", systemImage: "plus") { isCreatingIssue = true }
                    .disabled(controller.error == .trackerDisabled)
                    .help("Create an issue on \(provider?.sidebarTitle ?? "the tracker")")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func subtitle(for remote: HostedIssueRemote) -> String {
        let path = remote.provider == .azureBoards
            ? "Project \(remote.repository.owner)"
            : "\(remote.repository.owner)/\(remote.repository.name)"
        return "\(path) · \(remote.name)"
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            if controller.remotes.count > 1 {
                Menu {
                    Picker("Remote", selection: remoteBinding) {
                        ForEach(controller.remotes) { remote in
                            Text("\(remote.name) – \(remote.provider.sidebarTitle)").tag(remote.name)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label("Remote: \(controller.selectedRemote?.name ?? "")", systemImage: "network")
                }
                .modifier(HostedIssueFilterPill(isActive: controller.selectedRemote?.name != "origin"))
            }
            Menu {
                Picker("State", selection: filterBinding(\.state)) {
                    ForEach(HostedIssueStateFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("State: \(controller.filter.state.title)", systemImage: "circle.dashed")
            }
            .modifier(HostedIssueFilterPill(isActive: controller.filter.state != .open))
            Menu {
                Picker("Show", selection: filterBinding(\.relationship)) {
                    ForEach(HostedIssueRelationship.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(controller.filter.relationship.title, systemImage: "person")
            }
            .modifier(HostedIssueFilterPill(isActive: controller.filter.relationship != .all))
            Spacer(minLength: 0)
            if controller.isFiltered {
                Button("Reset Filters", systemImage: "xmark.circle.fill", action: controller.resetFilters)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout.scaled(by: textScale))
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var remoteBinding: Binding<String> {
        Binding(
            get: { controller.selectedRemote?.name ?? "" },
            set: { controller.selectRemote(named: $0) }
        )
    }

    private func filterBinding<Value>(_ keyPath: WritableKeyPath<HostedIssueFilter, Value>) -> Binding<Value> {
        Binding(
            get: { controller.filter[keyPath: keyPath] },
            set: { value in controller.updateFilter { $0[keyPath: keyPath] = value } }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !controller.hasDiscoveredRemotes {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.selectedRemote == nil {
            ContentUnavailableView(
                "No Issue Tracker",
                systemImage: "checklist",
                description: Text("Add a GitHub, GitLab, Bitbucket, or Azure Repos remote to see its issues here.")
            )
        } else if let problem = controller.accountProblem {
            accountProblemView(problem)
        } else if controller.isLoading, !controller.hasLoadedList {
            ProgressView("Loading issues…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = controller.error, controller.items.isEmpty {
            errorView(error)
        } else if controller.items.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                if let error = controller.error {
                    errorBanner(error)
                }
                issueBrowser
            }
        }
    }

    private func accountProblemView(_ problem: HostedIssueAccountProblem) -> some View {
        let providerName = provider?.accountKind.displayName ?? "provider"
        return ContentUnavailableView {
            switch problem {
            case .noAccount:
                Label("Connect \(providerName)", systemImage: "person.crop.circle.badge.plus")
            case .reconnect:
                Label("Reconnect \(providerName)", systemImage: "exclamationmark.triangle")
            }
        } description: {
            switch problem {
            case .noAccount(let host):
                Text("Connect a \(providerName) account for \(host.baseURL.host() ?? host.baseURL.absoluteString) to see this repository's issues.")
            case .reconnect:
                Text("The saved \(providerName) account needs to be connected again.")
            }
        } actions: {
            switch problem {
            case .noAccount: Button("Connect \(providerName)…", action: onOpenAccounts)
            case .reconnect: Button("Open Accounts…", action: onOpenAccounts)
            }
        }
    }

    @ViewBuilder
    private func errorView(_ error: HostedIssueError) -> some View {
        ContentUnavailableView {
            Label(errorTitle(error), systemImage: errorSymbol(error))
        } description: {
            Text(error.localizedDescription)
        } actions: {
            errorActions(error)
        }
    }

    @ViewBuilder
    private func errorActions(_ error: HostedIssueError) -> some View {
        switch error {
        case .trackerDisabled:
            if let url = repositoryWebURL {
                Button("Open Repository in Browser") { NSWorkspace.shared.open(url) }
            }
        case .missingScope, .reauthorizationRequired, .accountUpdateRequired:
            Button("Open Accounts…", action: onOpenAccounts)
        case .organizationAccessRequired:
            if canManageGitHubOrganizationAccess {
                Button("Manage Organization Access…", action: onOpenGitHubOrganizationAccess)
            }
            Button("Retry", action: controller.refresh)
        default:
            Button("Retry", action: controller.refresh)
        }
    }

    private func errorTitle(_ error: HostedIssueError) -> String {
        switch error {
        case .trackerDisabled: "Issues Are Turned Off"
        case .missingScope: "More Access Needed"
        case .organizationAccessRequired: "Organization Access Needed"
        case .reauthorizationRequired: "Reconnect Account"
        case .accountUpdateRequired: "Account Details Needed"
        case .rateLimited: "\(provider?.accountKind.displayName ?? "Provider") Is Busy"
        case .notFound: "Repository Not Found"
        case .closeUnavailable, .providerMessage: "Issues Unavailable"
        }
    }

    private func errorSymbol(_ error: HostedIssueError) -> String {
        switch error {
        case .trackerDisabled: "checklist.unchecked"
        case .missingScope, .organizationAccessRequired, .reauthorizationRequired, .accountUpdateRequired: "lock"
        case .rateLimited: "hourglass"
        default: "wifi.exclamationmark"
        }
    }

    private var repositoryWebURL: URL? {
        guard let remote = controller.selectedRemote else { return nil }
        let repository = remote.repository
        switch remote.provider {
        case .github, .gitlab:
            return repository.hostURL.appending(path: repository.owner).appending(path: repository.name)
        case .bitbucket:
            return URL(string: "https://bitbucket.org")!.appending(path: repository.owner).appending(path: repository.name)
        case .azureBoards:
            return repository.hostURL.appending(path: repository.owner).appending(path: "_workitems")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if controller.isFiltered {
            ContentUnavailableView {
                Label("No Matching Issues", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No issues match these filters.")
            } actions: {
                Button("Reset Filters", action: controller.resetFilters)
            }
        } else {
            ContentUnavailableView(
                "No Open Issues",
                systemImage: "checkmark.circle",
                description: Text("This tracker has no open issues.")
            )
        }
    }

    private func errorBanner(_ error: HostedIssueError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry", action: controller.refresh)
                .buttonStyle(.link)
        }
        .font(.callout.scaled(by: textScale))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - List and detail

    private var selectionBinding: Binding<Int?> {
        Binding(get: { controller.selectedIssueNumber }, set: { controller.select($0) })
    }

    private var issueBrowser: some View {
        GeometryReader { proxy in
            let maximumWidth = max(
                HostedIssueDetailView.minimumWidth,
                min(HostedIssueDetailView.maximumWidth, proxy.size.width - Self.issueListMinimumWidth)
            )
            let width = Binding<CGFloat>(
                get: { min(maximumWidth, max(HostedIssueDetailView.minimumWidth, CGFloat(storedDetailPanelWidth))) },
                set: { storedDetailPanelWidth = Double($0) }
            )
            HStack(spacing: 0) {
                issueList
                    .frame(minWidth: Self.issueListMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                if let number = controller.selectedIssueNumber, let provider {
                    HostedIssueDetailView(
                        controller: controller,
                        provider: provider,
                        summary: controller.detail?.summary ?? controller.items.first { $0.number == number },
                        gitFlowEnabled: gitFlowEnabled,
                        onOpenAccounts: onOpenAccounts,
                        onCreateBranch: { summary, target in onCreateBranch(String(summary.number), summary.title, target) },
                        onClose: { controller.select(nil) }
                    )
                    .id(number)
                    .frame(width: width.wrappedValue)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        RepositoryAIChatResizeHandle(
                            panelWidth: width,
                            minimumWidth: HostedIssueDetailView.minimumWidth,
                            maximumWidth: maximumWidth,
                            accessibilityLabel: "Resize Issue Details",
                            lineInset: 0
                        )
                        .frame(width: 8)
                    }
                }
            }
        }
    }

    private var issueList: some View {
        List(selection: selectionBinding) {
            ForEach(controller.items) { issue in
                HostedIssueRow(issue: issue, provider: provider ?? .github)
                    .tag(issue.number)
                    .onAppear {
                        if issue.number == controller.items.last?.number { controller.loadMore() }
                    }
            }
            if controller.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: Int.self) { numbers in
            if let issue = issue(for: numbers), let provider {
                HostedIssueActionsMenu(issue: issue, provider: provider, gitFlowEnabled: gitFlowEnabled) { target in
                    onCreateBranch(String(issue.number), issue.title, target)
                }
            }
        } primaryAction: { numbers in
            if let url = issue(for: numbers)?.webURL { NSWorkspace.shared.open(url) }
        }
    }

    private func issue(for numbers: Set<Int>) -> HostedIssueSummary? {
        guard let number = numbers.first else { return nil }
        return controller.items.first { $0.number == number }
    }
}

/// Open, copy, and branch actions shared by the row menu and the detail pane.
struct HostedIssueActionsMenu: View {
    let issue: HostedIssueSummary
    let provider: HostedIssueProvider
    let gitFlowEnabled: Bool
    let onCreateBranch: (IssueBranchTarget) -> Void

    var body: some View {
        if let url = issue.webURL {
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
        }
        Button("Copy Number") { HostedIssueClipboard.copy(provider.reference(for: issue.number)) }
        Button("Copy Reference and Title") {
            HostedIssueClipboard.copy("\(provider.reference(for: issue.number)) \(issue.title)")
        }
        Divider()
        HostedIssueBranchMenu(issue: issue, gitFlowEnabled: gitFlowEnabled, onCreateBranch: onCreateBranch)
    }
}

struct HostedIssueBranchMenu: View {
    let issue: HostedIssueSummary
    let gitFlowEnabled: Bool
    let onCreateBranch: (IssueBranchTarget) -> Void

    var body: some View {
        let typeName = issue.workItemType ?? (issue.labels.contains { $0.name.lowercased() == "bug" } ? "Bug" : "")
        let suggested = IssueBranchTarget.suggested(forIssueType: typeName, gitFlowEnabled: gitFlowEnabled)
        let others = IssueBranchTarget.options(gitFlowEnabled: gitFlowEnabled).filter { $0 != suggested }
        if others.isEmpty {
            Button("Create Branch…") { onCreateBranch(suggested) }
        } else {
            Menu("Create Branch") {
                Button(suggested.title) { onCreateBranch(suggested) }
                Divider()
                ForEach(others) { target in
                    Button(target.title) { onCreateBranch(target) }
                }
            }
        }
    }
}

enum HostedIssueClipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct HostedIssueRow: View {
    @Environment(\.appTextScale) private var textScale
    let issue: HostedIssueSummary
    let provider: HostedIssueProvider

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: issue.state == .open ? "circle.circle" : "checkmark.circle")
                .foregroundStyle(issue.state == .open ? Color.green : Color.purple)
                .frame(width: 16)
                .help(issue.stateName ?? (issue.state == .open ? "Open" : "Closed"))
            // The title owns the first line; labels only use what is left of the second.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(provider.reference(for: issue.number))
                        .font(.body.monospaced().scaled(by: textScale))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Text(issue.title)
                        .font(.body.scaled(by: textScale))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let stateName = issue.stateName {
                        Text(stateName)
                            .font(.caption.weight(.medium).scaled(by: textScale))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                HStack(spacing: 8) {
                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.caption.scaled(by: textScale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    if !issue.labels.isEmpty {
                        HostedIssueLabelLayout(wraps: false) {
                            ForEach(issue.labels, id: \.self) { HostedIssueLabelChip(label: $0) }
                        }
                        .clipped()
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var metadata: String {
        var parts: [String] = []
        if let type = issue.workItemType { parts.append(type) }
        if let author = issue.author?.displayName, !author.isEmpty { parts.append(author) }
        if let updatedAt = issue.updatedAt {
            parts.append("updated \(updatedAt.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}

struct HostedIssueLabelChip: View {
    @Environment(\.appTextScale) private var textScale
    @Environment(\.backgroundProminence) private var backgroundProminence
    let label: HostedIssueLabel

    var body: some View {
        let tint = backgroundProminence == .increased ? Color.primary : (Color(hostedIssueHex: label.color) ?? .secondary)
        Text(label.name)
            .font(.caption.scaled(by: textScale))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .fixedSize()
    }
}

/// Lays out label chips without ever growing past the offered width. Wrapping layouts flow onto
/// more lines; single-line layouts drop the chips that do not fit instead of truncating the title.
struct HostedIssueLabelLayout: Layout {
    var wraps: Bool
    var spacing: CGFloat = 4

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(for width: CGFloat, subviews: Subviews) -> [Line] {
        var lines = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = lines[lines.count - 1].indices.isEmpty ? size.width : lines[lines.count - 1].width + spacing + size.width
            if needed > width, !lines[lines.count - 1].indices.isEmpty {
                guard wraps else { break }
                lines.append(Line())
            } else if needed > width, !wraps {
                break
            }
            var line = lines[lines.count - 1]
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
            lines[lines.count - 1] = line
        }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(for: width, subviews: subviews)
        let usedWidth = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        let rowHeight = subviews.first?.sizeThatFits(.unspecified).height ?? 0
        return CGSize(width: proposal.width.map { min($0, usedWidth) } ?? usedWidth, height: max(height, wraps ? 0 : rowHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = lines(for: bounds.width, subviews: subviews)
        var placed = Set<Int>()
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                placed.insert(index)
            }
            y += line.height + spacing
        }
        // Chips keep their own size, so ones that do not fit go past the edge; callers clip.
        for index in subviews.indices where !placed.contains(index) {
            subviews[index].place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.minY), proposal: .unspecified)
        }
    }
}

/// Capsule chrome around a filter menu; tinted while the filter narrows the results.
private struct HostedIssueFilterPill: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        let tint = isActive ? Color.accentColor : Color.primary
        content
            .fixedSize()
            .padding(.leading, 9)
            .padding(.trailing, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(isActive ? 0.12 : 0.05)))
            .overlay(Capsule().strokeBorder(tint.opacity(isActive ? 0.35 : 0.12), lineWidth: 0.5))
            .contentShape(Capsule())
    }
}

extension Color {
    init?(hostedIssueHex hex: String?) {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
