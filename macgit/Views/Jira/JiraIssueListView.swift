// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct JiraIssueListView: View {
    @Environment(\.appTextScale) private var textScale
    @ObservedObject var controller: JiraIssueListController
    @ObservedObject var connectionController: JiraConnectionController
    /// The screen stays mounted while hidden, so loading follows visibility rather than appearance.
    let isActive: Bool
    let onOpenJiraSettings: () -> Void
    let gitFlowEnabled: Bool
    let onCreateBranch: (JiraIssue, JiraBranchTarget) -> Void
    @State private var selection: JiraIssue.ID?
    @AppStorage("jira.detailPanelWidth") private var storedDetailPanelWidth = Double(JiraIssueDetailPanel.defaultWidth)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if connectionController.connection != nil {
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
    }

    // MARK: - Header and filters

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Jira")
                    .font(.headline.scaled(by: textScale))
                if let connection = connectionController.connection {
                    Text(connection.siteHost)
                        .font(.caption.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if connectionController.connection != nil {
                TextField("Search key or summary", text: $controller.searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.scaled(by: textScale))
                    .frame(width: 220 * textScale)
                if controller.isLoading, controller.hasLoadedList {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh Jira issues", systemImage: "arrow.clockwise", action: controller.refresh)
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .disabled(controller.isLoading)
                    .help("Refresh")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            if controller.supportsSprints {
                sprintMenu
            }
            statusMenu
            projectMenu
            typeMenu
            Spacer(minLength: 0)
            if controller.isFiltered {
                Button("Reset Filters", action: controller.resetFilters)
                    .buttonStyle(.link)
            }
        }
        .font(.callout.scaled(by: textScale))
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var sprintMenu: some View {
        Menu {
            Picker("Sprint", selection: sprintBinding) {
                Text("Open Sprints").tag(JiraIssueFilter.SprintScope.openSprints)
                Text("Backlog").tag(JiraIssueFilter.SprintScope.backlog)
                Text("Any Sprint").tag(JiraIssueFilter.SprintScope.any)
                if !controller.sprintOptions.isEmpty {
                    Divider()
                    ForEach(controller.sprintOptions) { sprint in
                        Text(sprintTitle(sprint))
                            .tag(JiraIssueFilter.SprintScope.sprint(id: sprint.id, name: sprint.name))
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            filterLabel("Sprint", value: sprintScopeTitle)
        }
        .fixedSize()
    }

    private var statusMenu: some View {
        Menu {
            ForEach(JiraStatusCategory.allCases, id: \.self) { category in
                Toggle(category.title, isOn: membership(category, in: \.statusCategories))
            }
        } label: {
            filterLabel("Status", value: summary(
                JiraStatusCategory.allCases.filter(controller.filter.statusCategories.contains).map(\.title)
            ))
        }
        .fixedSize()
    }

    private var projectMenu: some View {
        Menu {
            if controller.projectOptions.isEmpty {
                Text("No projects yet")
            }
            ForEach(controller.projectOptions) { project in
                Toggle("\(project.key) – \(project.name)", isOn: membership(project.key, in: \.projectKeys))
            }
        } label: {
            filterLabel("Project", value: summary(controller.filter.projectKeys.sorted()))
        }
        .fixedSize()
    }

    private var typeMenu: some View {
        Menu {
            if controller.issueTypeOptions.isEmpty {
                Text("No issue types yet")
            }
            ForEach(controller.issueTypeOptions, id: \.self) { type in
                Toggle(type, isOn: membership(type, in: \.issueTypeNames))
            }
        } label: {
            filterLabel("Type", value: summary(controller.filter.issueTypeNames.sorted()))
        }
        .fixedSize()
    }

    private func filterLabel(_ title: String, value: String) -> some View {
        Text("\(title): \(value)")
    }

    private func summary(_ values: [String]) -> String {
        switch values.count {
        case 0: "Any"
        case 1, 2: values.joined(separator: ", ")
        default: "\(values.count) selected"
        }
    }

    private var sprintScopeTitle: String {
        switch controller.filter.sprintScope {
        case .openSprints: "Open Sprints"
        case .backlog: "Backlog"
        case .any: "Any"
        case .sprint(_, let name): name
        }
    }

    private func sprintTitle(_ sprint: JiraSprintRef) -> String {
        switch sprint.state {
        case "active": "\(sprint.name) (Active)"
        case "future": "\(sprint.name) (Future)"
        default: sprint.name
        }
    }

    private var sprintBinding: Binding<JiraIssueFilter.SprintScope> {
        Binding(
            get: { controller.filter.sprintScope },
            set: { scope in controller.updateFilter { $0.sprintScope = scope } }
        )
    }

    private func membership<Value: Hashable>(
        _ value: Value,
        in keyPath: WritableKeyPath<JiraIssueFilter, Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { controller.filter[keyPath: keyPath].contains(value) },
            set: { isOn in
                controller.updateFilter { filter in
                    if isOn {
                        filter[keyPath: keyPath].insert(value)
                    } else {
                        filter[keyPath: keyPath].remove(value)
                    }
                }
            }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let connection = connectionController.connection {
            if connection.needsReconnect || controller.error == .needsReconnect {
                ContentUnavailableView {
                    Label("Reconnect Jira", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Jira no longer accepts the saved API token for \(connection.siteHost).")
                } actions: {
                    Button("Open Jira Settings…", action: onOpenJiraSettings)
                }
            } else if controller.isLoading, !controller.hasLoadedList {
                ProgressView("Loading Jira issues…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = controller.error, controller.items.isEmpty {
                ContentUnavailableView {
                    Label(errorTitle(error), systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry", action: controller.refresh)
                }
            } else if controller.items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    if let error = controller.error {
                        errorBanner(error)
                    }
                    issueBrowser(connection: connection)
                }
            }
        } else {
            ContentUnavailableView {
                Label {
                    Text("Connect Jira")
                } icon: {
                    Image("jira")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                }
            } description: {
                Text("Connect a Jira Cloud site in Settings → Integrations to see the issues assigned to you.")
            } actions: {
                Button("Connect Jira…", action: onOpenJiraSettings)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if controller.hasAnyAssignedIssues {
            ContentUnavailableView {
                Label("No Matching Issues", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("None of your Jira issues match these filters.")
            } actions: {
                Button("Reset Filters", action: controller.resetFilters)
            }
        } else {
            ContentUnavailableView(
                "No Assigned Issues",
                systemImage: "checkmark.circle",
                description: Text("No Jira issues are assigned to you on this site.")
            )
        }
    }

    private func errorTitle(_ error: JiraError) -> String {
        switch error {
        case .rateLimited: "Jira Is Busy"
        case .forbidden: "No Permission"
        case .invalidQuery: "Filter Not Supported"
        default: "Jira Unavailable"
        }
    }

    private func errorBanner(_ error: JiraError) -> some View {
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

    private var selectedIssue: JiraIssue? {
        guard let selection else { return nil }
        return controller.items.first { $0.id == selection }
    }

    private static let issueListMinimumWidth: CGFloat = 360

    /// The list, plus a detail panel on the right while an issue is selected.
    /// The panel's width is stored so closing and reopening it keeps the size the user dragged to.
    private func issueBrowser(connection: JiraConnection) -> some View {
        GeometryReader { proxy in
            let maximumWidth = max(
                JiraIssueDetailPanel.minimumWidth,
                min(JiraIssueDetailPanel.maximumWidth, proxy.size.width - Self.issueListMinimumWidth)
            )
            let width = detailPanelWidthBinding(maximumWidth: maximumWidth)
            HStack(spacing: 0) {
                issueList(connection: connection)
                    .frame(minWidth: Self.issueListMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                if let issue = selectedIssue {
                    JiraIssueDetailPanel(
                        issue: issue,
                        gitFlowEnabled: gitFlowEnabled,
                        onOpen: { open(issue, in: connection) },
                        onCopyKey: { copy(issue.key) },
                        onCopyKeyAndSummary: { copy("\(issue.key) \(issue.summary)") },
                        onCreateBranch: { onCreateBranch(issue, $0) },
                        onClose: { selection = nil }
                    )
                    .frame(width: width.wrappedValue)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        RepositoryAIChatResizeHandle(
                            panelWidth: width,
                            minimumWidth: JiraIssueDetailPanel.minimumWidth,
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

    private func detailPanelWidthBinding(maximumWidth: CGFloat) -> Binding<CGFloat> {
        Binding(
            get: { min(maximumWidth, max(JiraIssueDetailPanel.minimumWidth, CGFloat(storedDetailPanelWidth))) },
            set: { storedDetailPanelWidth = Double($0) }
        )
    }

    @ViewBuilder
    private func createBranchMenu(for issue: JiraIssue) -> some View {
        let suggested = JiraBranchTarget.suggested(forIssueType: issue.issueTypeName, gitFlowEnabled: gitFlowEnabled)
        let others = JiraBranchTarget.options(gitFlowEnabled: gitFlowEnabled).filter { $0 != suggested }
        if others.isEmpty {
            Button("Create Branch…") { onCreateBranch(issue, suggested) }
        } else {
            Menu("Create Branch") {
                Button(suggested.title) { onCreateBranch(issue, suggested) }
                Divider()
                ForEach(others) { target in
                    Button(target.title) { onCreateBranch(issue, target) }
                }
            }
        }
    }

    private func issueList(connection: JiraConnection) -> some View {
        List(selection: $selection) {
            ForEach(controller.items) { issue in
                JiraIssueRow(issue: issue)
                    .tag(issue.id)
                    .onAppear {
                        if issue.id == controller.items.last?.id { controller.loadMore() }
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
        .contextMenu(forSelectionType: JiraIssue.ID.self) { ids in
            if let issue = issue(for: ids) {
                Button("Open in Jira") { open(issue, in: connection) }
                Button("Copy Key") { copy(issue.key) }
                Button("Copy Key and Summary") { copy("\(issue.key) \(issue.summary)") }
                Divider()
                createBranchMenu(for: issue)
            }
        } primaryAction: { ids in
            if let issue = issue(for: ids) { open(issue, in: connection) }
        }
    }

    private func issue(for ids: Set<JiraIssue.ID>) -> JiraIssue? {
        guard let id = ids.first else { return nil }
        return controller.items.first { $0.id == id }
    }

    private func open(_ issue: JiraIssue, in connection: JiraConnection) {
        NSWorkspace.shared.open(connection.browseURL(for: issue.key))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct JiraIssueRow: View {
    @Environment(\.appTextScale) private var textScale
    let issue: JiraIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: issue.typeSymbol)
                .foregroundStyle(issue.typeTint)
                .frame(width: 16)
                .help(issue.issueTypeName)
            Text(issue.key)
                .font(.body.monospaced().scaled(by: textScale))
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(issue.summary)
                .font(.body.scaled(by: textScale))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 8)
            // Trailing metadata keeps its full width; only the summary truncates.
            if let sprint = issue.displaySprint {
                Text(sprint.name)
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if let priority = issue.priorityName {
                Text(priority)
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            JiraStatusBadge(issue: issue)
        }
        .padding(.vertical, 3)
    }
}

private struct JiraStatusBadge: View {
    @Environment(\.appTextScale) private var textScale
    @Environment(\.backgroundProminence) private var backgroundProminence
    let issue: JiraIssue

    var body: some View {
        // On a selected row the tint would vanish into the accent highlight; fall back to primary like RefLabel.
        let isProminent = backgroundProminence == .increased
        Text(issue.statusName)
            .font(.caption.weight(.medium).scaled(by: textScale))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isProminent ? Color.primary.opacity(0.12) : issue.statusTint.opacity(0.15), in: Capsule())
            .foregroundStyle(isProminent ? AnyShapeStyle(.primary) : AnyShapeStyle(issue.statusTint))
            .fixedSize()
    }
}

/// Basic issue details and the same actions as the row's context menu.
private struct JiraIssueDetailPanel: View {
    static let minimumWidth: CGFloat = 280
    static let defaultWidth: CGFloat = 360
    static let maximumWidth: CGFloat = 640

    @Environment(\.appTextScale) private var textScale
    let issue: JiraIssue
    let gitFlowEnabled: Bool
    let onOpen: () -> Void
    let onCopyKey: () -> Void
    let onCopyKeyAndSummary: () -> Void
    let onCreateBranch: (JiraBranchTarget) -> Void
    let onClose: () -> Void
    @State private var otherTypesAnchor: NSView?

    private var suggestedTarget: JiraBranchTarget {
        JiraBranchTarget.suggested(forIssueType: issue.issueTypeName, gitFlowEnabled: gitFlowEnabled)
    }

    private var otherTargets: [JiraBranchTarget] {
        JiraBranchTarget.options(gitFlowEnabled: gitFlowEnabled).filter { $0 != suggestedTarget }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: issue.typeSymbol)
                    .foregroundStyle(issue.typeTint)
                Text(issue.key)
                    .font(.headline.monospaced().scaled(by: textScale))
                    .textSelection(.enabled)
                Spacer()
                Button("Close details", systemImage: "xmark", action: onClose)
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(issue.summary)
                        .font(.title3.weight(.semibold).scaled(by: textScale))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    actions

                    Divider()

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            fieldLabel("Status")
                            JiraStatusBadge(issue: issue)
                        }
                        field("Type", issue.issueTypeName)
                        if let priority = issue.priorityName { field("Priority", priority) }
                        field("Project", issue.projectName.isEmpty ? issue.projectKey : "\(issue.projectName) (\(issue.projectKey))")
                        if !issue.sprints.isEmpty {
                            field("Sprint", issue.sprints.map(\.name).joined(separator: ", "))
                        }
                        if let updated = issue.updated {
                            field("Updated", updated.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .font(.callout.scaled(by: textScale))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Buttons stretch to the panel's width: the branch action on its own row, the secondary
    /// actions side by side when they fit and stacked otherwise.
    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { onCreateBranch(suggestedTarget) } label: {
                    Label(suggestedTarget.title, systemImage: "arrow.branch")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)
                // The issue type picks the default; the arrow offers every other flow.
                if !otherTargets.isEmpty {
                    // A SwiftUI Menu renders as a fixed-height pop-up button, so this is a Button
                    // that opens a native menu; its label fills the row so both bezels match.
                    Button(action: showOtherBranchTypes) {
                        Label("Other Branch Types", systemImage: "chevron.down")
                            .labelStyle(.iconOnly)
                            .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .background(MenuAnchorView(view: $otherTypesAnchor))
                    .help("Other Branch Types")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { secondaryActions }
                VStack(spacing: 8) { secondaryActions }
            }
        }
        .controlSize(.large)
        .font(.body.scaled(by: textScale))
    }

    private func showOtherBranchTypes() {
        guard let anchor = otherTypesAnchor else { return }
        let menu = SidebarNativeMenu()
        for target in otherTargets {
            menu.item(target.title) { onCreateBranch(target) }
        }
        let below = anchor.isFlipped ? anchor.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: anchor)
    }

    @ViewBuilder
    private var secondaryActions: some View {
        actionButton("Open in Jira", systemImage: "arrow.up.right.square", action: onOpen)
        actionButton("Copy Key", systemImage: "doc.on.doc", action: onCopyKey)
        actionButton("Copy Key and Summary", systemImage: "doc.text", action: onCopyKeyAndSummary)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func field(_ title: String, _ value: String) -> some View {
        GridRow {
            fieldLabel(title)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension JiraIssue {
    var typeSymbol: String {
        switch issueTypeName.lowercased() {
        case "bug": "ladybug"
        case "story": "bookmark"
        case "epic": "bolt"
        case "sub-task", "subtask": "arrow.turn.down.right"
        default: "checkmark.square"
        }
    }

    var typeTint: Color {
        switch issueTypeName.lowercased() {
        case "bug": .red
        case "story": .green
        case "epic": .purple
        default: .blue
        }
    }

    var statusTint: Color {
        switch statusCategory {
        case .done: .green
        case .inProgress: .blue
        case .toDo, nil: .secondary
        }
    }
}

/// Exposes the AppKit view behind a SwiftUI control so a native menu can be anchored to it.
private struct MenuAnchorView: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView()
        DispatchQueue.main.async { view = anchor }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
