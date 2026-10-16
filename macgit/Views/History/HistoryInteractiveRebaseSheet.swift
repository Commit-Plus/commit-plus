// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct HistoryInteractiveRebaseSheet: View {
    @State private var plan: HistoryRebasePlan
    let controller: HistoryCommitActionController

    init(plan: HistoryRebasePlan, controller: HistoryCommitActionController) {
        _plan = State(initialValue: plan)
        self.controller = controller
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(plan.quickAction?.title ?? "Interactive Rebase")
                .font(.title2.weight(.semibold))
            Text("Rewrite \(plan.entries.count) commits on '\(plan.branch)', oldest first.")
            Text("Rewriting changes commit hashes. Published commits may require a force push. Remote status is based on the last fetch.")
                .font(.callout).foregroundStyle(.secondary)
            if plan.quickAction == .edit {
                Text("Rebase will pause at this commit. Make your changes, stage them and amend the commit in File Status, then choose Continue Rebase.")
            } else if plan.quickAction == .drop {
                Text("The selected commit and its changes will be removed from this branch.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($plan.entries) { $entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if plan.quickAction == nil {
                                    Picker("Action", selection: $entry.action) {
                                        ForEach(HistoryRebasePlan.Action.allCases) { action in
                                            Text(action.title).tag(action)
                                        }
                                    }
                                    .labelsHidden().frame(width: 170)
                                } else {
                                    Text(entry.action.title).frame(width: 150, alignment: .leading)
                                }
                                Text(entry.commit.shortHash).monospaced().foregroundStyle(.secondary)
                                Text(entry.commit.message).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                if plan.quickAction == nil {
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
                        Divider()
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: 380)
            if let message = plan.validationMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: controller.dismiss).keyboardShortcut(.cancelAction)
                Button(plan.quickAction?.title ?? "Start Rebase") { controller.interactiveRebase(plan) }
                    .keyboardShortcut(.defaultAction).disabled(plan.validationMessage != nil)
            }
        }
        .padding(24)
        .frame(width: 740)
    }

    private func move(_ hash: String, offset: Int) {
        guard let index = plan.entries.firstIndex(where: { $0.id == hash }),
              plan.entries.indices.contains(index + offset) else { return }
        plan.entries.swapAt(index, index + offset)
    }
}
