// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Creates an issue on the selected remote's tracker. Nothing is sent until the user chooses Create.
struct NewHostedIssueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTextScale) private var textScale
    @ObservedObject var controller: HostedIssueController
    @State private var title = ""
    @State private var description = ""
    @State private var workItemType = ""
    @State private var isLoadingTypes = false

    private var needsType: Bool { controller.provider?.supportsWorkItemTypes == true }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!needsType || !workItemType.isEmpty)
            && !controller.isWriting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Issue")
                .font(.headline.scaled(by: textScale))
            if let remote = controller.selectedRemote {
                Text(remote.provider == .azureBoards
                     ? "Creates a work item in project \(remote.repository.owner)."
                     : "Creates an issue in \(remote.repository.owner)/\(remote.repository.name).")
                    .font(.callout.scaled(by: textScale))
                    .foregroundStyle(.secondary)
            }
            Form {
                if needsType {
                    Picker("Type", selection: $workItemType) {
                        Text("Choose…").tag("")
                        ForEach(controller.workItemTypes, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(isLoadingTypes)
                }
                TextField("Title", text: $title)
            }
            .formStyle(.columns)
            Text(needsType ? "Description" : "Description (Markdown)")
                .font(.callout.scaled(by: textScale))
                .foregroundStyle(.secondary)
            TextEditor(text: $description)
                .font(.body.scaled(by: textScale))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            if let error = controller.writeError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.scaled(by: textScale))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if controller.isWriting {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task {
                        let draft = HostedIssueDraft(title: title, body: description,
                                                     workItemType: needsType ? workItemType : nil)
                        if await controller.createIssue(draft) { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            controller.clearWriteError()
            guard needsType else { return }
            isLoadingTypes = true
            await controller.loadWorkItemTypes()
            isLoadingTypes = false
            if workItemType.isEmpty {
                workItemType = ["Issue", "Bug", "User Story", "Task"].first(where: controller.workItemTypes.contains) ?? ""
            }
        }
    }
}
