// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct HistoryInteractiveRebaseSheet: View {
    @State private var plan: HistoryRebasePlan
    @State private var selectedCommit: String?
    @State private var detailModel: HistoryCommitDetailModel
    @State private var showsChanges = false
    let height: CGFloat
    let controller: HistoryCommitActionController

    init(plan: HistoryRebasePlan, controller: HistoryCommitActionController, height: CGFloat) {
        _plan = State(initialValue: HistoryRebasePlan(
            branch: plan.branch, head: plan.head, upstream: plan.upstream, onto: plan.onto,
            originalHashes: plan.originalHashes, quickAction: nil, entries: plan.entries))
        self.height = height
        self.controller = controller
        _selectedCommit = State(initialValue: plan.entries.first(where: { $0.action != .pick })?.id ?? plan.entries.first?.id)
        _detailModel = State(initialValue: HistoryCommitDetailModel(repositoryURL: controller.dependencies.repositoryURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                Label("Rebase: \(plan.branch)", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                Text("\(plan.entries.count) commits ↓")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Commits are applied from top to bottom.")
                    .accessibilityLabel("\(plan.entries.count) commits, applied from top to bottom")
                Spacer()
                Text("On: \((plan.onto ?? plan.upstream).map { String($0.prefix(12)) } ?? "Root")")
                    .foregroundStyle(.secondary).monospaced()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach($plan.entries) { $entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle().fill(actionColor(entry.action)).frame(width: 8, height: 8)
                                Picker("Action", selection: $entry.action) {
                                    ForEach(HistoryRebasePlan.Action.allCases) { action in
                                        Text(action.title).tag(action)
                                    }
                                }
                                .labelsHidden().frame(width: 150)
                                .controlSize(.small)
                                Text(entry.commit.message).lineLimit(1).help(entry.commit.message).frame(maxWidth: .infinity, alignment: .leading)
                                Text(entry.commit.author).foregroundStyle(.secondary).frame(width: 120, alignment: .leading).lineLimit(1)
                                Text(entry.commit.shortHash).monospaced().foregroundStyle(.secondary)
                                Group {
                                    Button("Move Earlier", systemImage: "arrow.up") { move(entry.id, offset: -1) }
                                        .labelStyle(.iconOnly).disabled(plan.entries.first?.id == entry.id)
                                    Button("Move Later", systemImage: "arrow.down") { move(entry.id, offset: 1) }
                                        .labelStyle(.iconOnly).disabled(plan.entries.last?.id == entry.id)
                                }
                            }
                            if entry.action == .reword {
                                TextField("Commit message", text: $entry.message, axis: .vertical)
                                    .lineLimit(3...8).textFieldStyle(.roundedBorder)
                            } else if entry.action == .squash {
                                TextField("Leave empty to combine commit messages", text: $entry.squashMessage, axis: .vertical)
                                    .lineLimit(3...8).textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(selectedCommit == entry.id ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedCommit = entry.id }
                    }
                }
            }
            .frame(height: commitListHeight)
            Divider()
            detailPanel
                .frame(maxHeight: .infinity)
            Divider()
            if let message = plan.validationMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            }
            HStack(spacing: 8) {
                Label("Rewrites history · Published commits may need a force push", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Rewriting changes commit hashes. Published commits may require a force push. Remote status is based on the last fetch.")
                Spacer()
                Button("Cancel", role: .cancel, action: controller.dismiss).keyboardShortcut(.cancelAction)
                Button("Rebase") { controller.interactiveRebase(plan) }
                    .keyboardShortcut(.defaultAction).disabled(plan.validationMessage != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(width: 980, height: height)
        .task(id: selectedCommit) {
            detailModel.show(plan.entries.first(where: { $0.id == selectedCommit })?.commit, debounce: false)
            detailModel.loadFullMessage()
        }
        .onDisappear { detailModel.suspend() }
    }

    private var commitListHeight: CGFloat {
        let messageEditors = plan.entries.filter { $0.action == .reword || $0.action == .squash }.count
        let rowHeight: CGFloat = 32
        let maximumVisibleCommits: CGFloat = 6
        return min(rowHeight * maximumVisibleCommits,
            max(rowHeight, CGFloat(plan.entries.count) * rowHeight + CGFloat(messageEditors) * 90))
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Picker("Details", selection: $showsChanges) {
                    Text("Commit").tag(false)
                    Text("Changes").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                if let entry = plan.entries.first(where: { $0.id == selectedCommit }) {
                    Text(actionHelp(entry.action))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).help(actionHelp(entry.action))
                }
                Spacer(minLength: 0)
            }
            if let entry = plan.entries.first(where: { $0.id == selectedCommit }) {
                if showsChanges {
                    HistoryCommitDetailView(model: detailModel,
                        repositoryURL: controller.dependencies.repositoryURL,
                        undoManager: controller.dependencies.undoManager,
                        syncState: controller.dependencies.syncState,
                        runOperation: controller.dependencies.runOperation, onOpenFile: { _ in })
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(entry.commit.author + " <" + entry.commit.email + ">")
                            Text(entry.commit.date, format: .dateTime.year().month().day().hour().minute())
                                .foregroundStyle(.secondary)
                            Text(entry.commit.hash).monospaced().foregroundStyle(.secondary)
                            if !entry.commit.refs.isEmpty {
                                Text(entry.commit.refs.joined(separator: ", ")).foregroundStyle(.secondary)
                            }
                            Divider()
                            Text(detailModel.fullMessage ?? entry.commit.message)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func actionColor(_ action: HistoryRebasePlan.Action) -> Color {
        switch action {
        case .pick: .green
        case .edit, .reword: .orange
        case .squash, .fixup: .purple
        case .drop: .red
        }
    }

    private func actionHelp(_ action: HistoryRebasePlan.Action) -> String {
        switch action {
        case .pick: "Pick keeps this commit and reapplies its changes."
        case .edit: "Edit pauses here. Change files, stage and amend in File Status, then choose Continue Rebase."
        case .reword: "Reword replaces this commit’s message with the message entered above."
        case .squash: "Squash combines this commit and its message with the preceding commit."
        case .fixup: "Fixup combines changes with the preceding commit and discards this message."
        case .drop: "Drop removes this commit and its changes from the branch."
        }
    }

    private func move(_ hash: String, offset: Int) {
        guard let index = plan.entries.firstIndex(where: { $0.id == hash }),
              plan.entries.indices.contains(index + offset) else { return }
        plan.entries.swapAt(index, index + offset)
    }
}
