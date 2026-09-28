// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SettingsSyncConflictSheet: View {
    @ObservedObject var controller: AccountSessionController
    @State private var collapsedSectionIDs: Set<String> = []
    @State private var selectedSource: SettingsSyncSourceChoice? = .cloud

    private var localSnapshot: AppSettingsSnapshot {
        controller.localSettingsSnapshot
    }

    private var cloudSnapshot: AppSettingsSnapshot {
        controller.pendingCloudSettings ?? localSnapshot
    }

    private var sections: [SettingsComparisonSection] {
        SettingsComparisonSection.make(local: localSnapshot, cloud: cloudSnapshot)
    }

    private var changedSettingCount: Int {
        sections.flatMap(\.rows).count(where: \.isChanged)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title
            comparison
            actions
        }
        .padding()
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 660)
        .interactiveDismissDisabled()
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Choose Settings to Sync")
                    .font(.title2)
                    .bold()

                Spacer()

                Text("\(changedSettingCount) differences")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Text("This Mac and your cloud account have different settings. Compare each group, then choose which version Commit+ should use on all synced devices.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comparison: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(sections) { section in
                        SettingsComparisonSectionView(
                            section: section,
                            isExpanded: !collapsedSectionIDs.contains(section.id),
                            onToggle: { toggle(section.id) }
                        )
                    }
                } header: {
                    VStack(spacing: 0) {
                        SettingsComparisonHeader(selectedSource: $selectedSource)
                        Divider()
                    }
                    .background(.background)
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
        .frame(minHeight: 400, maxHeight: .infinity)
    }

    private var actions: some View {
        HStack {
            Button("Cancel") {
                resolve(.cancel)
            }

            Spacer()

            Button("Continue", action: continueWithSelectedSource)
                .disabled(selectedSource == nil)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func toggle(_ sectionID: String) {
        if collapsedSectionIDs.contains(sectionID) {
            collapsedSectionIDs.remove(sectionID)
        } else {
            collapsedSectionIDs.insert(sectionID)
        }
    }

    private func resolve(_ choice: InitialSettingsChoice) {
        Task { await controller.resolveInitialSettingsChoice(choice) }
    }

    private func continueWithSelectedSource() {
        switch selectedSource {
        case .thisMac:
            resolve(.keepThisMac)
        case .cloud:
            resolve(.useCloud)
        case nil:
            break
        }
    }
}

private struct SettingsComparisonHeader: View {
    @Binding var selectedSource: SettingsSyncSourceChoice?

    var body: some View {
        HStack(spacing: 0) {
            column(
                title: "Current Mac",
                detail: "Keep this Mac's settings",
                systemImage: "desktopcomputer",
                source: .thisMac
            )
            Divider()
            column(
                title: "Cloud",
                detail: "Use cloud settings",
                systemImage: "cloud.fill",
                source: .cloud
            )
        }
        .frame(height: 52)
        .background(.bar)
    }

    private func column(
        title: String,
        detail: String,
        systemImage: String,
        source: SettingsSyncSourceChoice
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { selectedSource == source },
                set: { isSelected in
                    selectedSource = isSelected ? source : nil
                }
            )
        ) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .bold()
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private enum SettingsSyncSourceChoice: Equatable {
    case thisMac
    case cloud
}

private struct SettingsComparisonSectionView: View {
    let section: SettingsComparisonSection
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    Image(systemName: section.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(section.title)
                        .bold()

                    Spacer()

                    if section.changedCount > 0 {
                        Text("\(section.changedCount) changed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .background(Color.accentColor.opacity(0.08))

            if isExpanded {
                ForEach(section.rows) { row in
                    SettingsComparisonRowView(row: row)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct SettingsComparisonRowView: View {
    let row: SettingsComparisonRow

    var body: some View {
        HStack(spacing: 0) {
            cell(value: row.localValue, side: .local)
            Divider()
            cell(value: row.cloudValue, side: .cloud)
        }
        .frame(minHeight: 32)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.55)
        }
    }

    private func cell(value: SettingsComparisonValue, side: ComparisonSide) -> some View {
        HStack(spacing: 8) {
            Text(row.isChanged ? side.marker : "")
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .foregroundStyle(side.tint)
                .frame(width: 12)
                .accessibilityHidden(true)

            Text(row.title)
                .lineLimit(1)

            Spacer(minLength: 8)

            Label(value.title, systemImage: value.systemImage)
                .labelStyle(SettingsComparisonValueLabelStyle())
                .foregroundStyle(value.isActive ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(row.isChanged ? side.background : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(value.title)\(row.isChanged ? ", different" : "")")
    }
}

private struct SettingsComparisonValueLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

private enum ComparisonSide {
    case local
    case cloud

    var marker: String {
        switch self {
        case .local: "−"
        case .cloud: "+"
        }
    }

    var tint: Color {
        switch self {
        case .local: .red
        case .cloud: .green
        }
    }

    var background: Color {
        tint.opacity(0.08)
    }
}

private struct SettingsComparisonSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let rows: [SettingsComparisonRow]

    var changedCount: Int {
        rows.count(where: \.isChanged)
    }

    static func make(
        local: AppSettingsSnapshot,
        cloud: AppSettingsSnapshot
    ) -> [SettingsComparisonSection] {
        [
            SettingsComparisonSection(
                id: "appearance",
                title: "Appearance",
                systemImage: "paintbrush",
                rows: [
                    .value(
                        "Theme",
                        local: .named(local.appearance.title, systemImage: local.appearance.systemImage),
                        cloud: .named(cloud.appearance.title, systemImage: cloud.appearance.systemImage)
                    )
                ]
            ),
            SettingsComparisonSection(
                id: "workspace",
                title: "Workspace",
                systemImage: "sidebar.left",
                rows: [
                    .shown("Reflog", local: local.showWorkspaceReflog, cloud: cloud.showWorkspaceReflog),
                    .shown("Pull Requests", local: local.showWorkspacePullRequests, cloud: cloud.showWorkspacePullRequests),
                    .shown("Git LFS", local: local.showWorkspaceGitLFS, cloud: cloud.showWorkspaceGitLFS),
                    .shown("Git Flow", local: local.showGitFlow, cloud: cloud.showGitFlow)
                ]
            ),
            SettingsComparisonSection(
                id: "repository-sections",
                title: "Repository Sections",
                systemImage: "square.stack.3d.up",
                rows: [
                    .shown("Tags", local: local.showTags, cloud: cloud.showTags),
                    .shown("Worktrees", local: local.showWorktrees, cloud: cloud.showWorktrees),
                    .shown("Submodules", local: local.showSubmodules, cloud: cloud.showSubmodules),
                    .shown("Subtrees", local: local.showSubtrees, cloud: cloud.showSubtrees)
                ]
            ),
            SettingsComparisonSection(
                id: "toolbar",
                title: "Repository Toolbar",
                systemImage: "menubar.rectangle",
                rows: [
                    .shown("Button text", local: local.showToolbarButtonText, cloud: cloud.showToolbarButtonText),
                    .shown("Branch", local: local.showHeaderBranchButton, cloud: cloud.showHeaderBranchButton),
                    .shown("Merge", local: local.showHeaderMergeButton, cloud: cloud.showHeaderMergeButton),
                    .shown("Stash", local: local.showHeaderStashButton, cloud: cloud.showHeaderStashButton)
                ]
            ),
            SettingsComparisonSection(
                id: "pinned-actions",
                title: "Pinned Actions",
                systemImage: "pin",
                rows: [
                    .shown("Undo", local: local.showHeaderUndoButton, cloud: cloud.showHeaderUndoButton),
                    .shown("Remote", local: local.showHeaderRemoteButton, cloud: cloud.showHeaderRemoteButton),
                    .shown("Finder", local: local.showHeaderFinderButton, cloud: cloud.showHeaderFinderButton),
                    .shown("External Editor", local: local.showHeaderEditorButton, cloud: cloud.showHeaderEditorButton),
                    .shown("Terminal", local: local.showHeaderTerminalButton, cloud: cloud.showHeaderTerminalButton),
                    .shown("Settings", local: local.showHeaderSettingsButton, cloud: cloud.showHeaderSettingsButton)
                ]
            ),
            SettingsComparisonSection(
                id: "history",
                title: "History",
                systemImage: "clock.arrow.circlepath",
                rows: [
                    .value(
                        "Branch filter",
                        local: .named(local.historyBranchFilter.comparisonTitle, systemImage: "line.3.horizontal.decrease.circle"),
                        cloud: .named(cloud.historyBranchFilter.comparisonTitle, systemImage: "line.3.horizontal.decrease.circle")
                    ),
                    .shown("Remote branches", local: local.historyIncludeRemotes, cloud: cloud.historyIncludeRemotes)
                ]
            ),
            SettingsComparisonSection(
                id: "refresh",
                title: "Refresh",
                systemImage: "arrow.clockwise",
                rows: [
                    .enabled("Auto fetch", local: local.autoFetchEnabled, cloud: cloud.autoFetchEnabled),
                    .enabled("When app becomes active", local: local.refreshOnAppActive, cloud: cloud.refreshOnAppActive)
                ]
            )
        ]
    }
}

private struct SettingsComparisonRow: Identifiable {
    let id: String
    let title: String
    let localValue: SettingsComparisonValue
    let cloudValue: SettingsComparisonValue

    var isChanged: Bool {
        localValue != cloudValue
    }

    static func value(
        _ title: String,
        local: SettingsComparisonValue,
        cloud: SettingsComparisonValue
    ) -> SettingsComparisonRow {
        SettingsComparisonRow(id: title, title: title, localValue: local, cloudValue: cloud)
    }

    static func shown(_ title: String, local: Bool, cloud: Bool) -> SettingsComparisonRow {
        value(title, local: .shown(local), cloud: .shown(cloud))
    }

    static func enabled(_ title: String, local: Bool, cloud: Bool) -> SettingsComparisonRow {
        value(title, local: .enabled(local), cloud: .enabled(cloud))
    }
}

private struct SettingsComparisonValue: Equatable {
    let title: String
    let systemImage: String
    let isActive: Bool

    static func named(_ title: String, systemImage: String) -> SettingsComparisonValue {
        SettingsComparisonValue(title: title, systemImage: systemImage, isActive: true)
    }

    static func shown(_ value: Bool) -> SettingsComparisonValue {
        SettingsComparisonValue(
            title: value ? "Shown" : "Hidden",
            systemImage: value ? "checkmark.circle.fill" : "circle",
            isActive: value
        )
    }

    static func enabled(_ value: Bool) -> SettingsComparisonValue {
        SettingsComparisonValue(
            title: value ? "Enabled" : "Disabled",
            systemImage: value ? "checkmark.circle.fill" : "circle",
            isActive: value
        )
    }
}

private extension HistoryBranchFilter {
    var comparisonTitle: String {
        switch self {
        case .all: "All branches"
        case .current: "Current branch"
        case .branch(let branch): branch
        }
    }
}
