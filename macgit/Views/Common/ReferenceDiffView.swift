// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ReferenceDiffView: View {
    @State private var controller: ReferenceComparisonController
    let onClose: () -> Void
    @State private var showsCommits = false

    init(repositoryURL: URL, baseRef: String, targetRef: String, title: String, onClose: @escaping () -> Void) {
        _controller = State(initialValue: ReferenceComparisonController(repositoryURL: repositoryURL,
            baseRef: baseRef, targetRef: targetRef, isBranchComparison: false, title: title))
        self.onClose = onClose
    }

    init(controller: ReferenceComparisonController, onClose: @escaping () -> Void) {
        _controller = State(initialValue: controller)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if controller.isBranchComparison {
                Picker("Comparison content", selection: $showsCommits) {
                    Text("Files (\(controller.files.count))").tag(false)
                    Text("Commits").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .padding(8)
            }
            if controller.isCancelled {
                EmptyStateView(icon: "pause.circle", message: "Comparison stopped", detail: "Select Refresh to load this comparison again.")
            } else if let error = controller.error, controller.snapshot == nil {
                EmptyStateView(icon: "exclamationmark.triangle", message: "Could not compare references", detail: error)
            } else if controller.baseRef.isEmpty || controller.targetRef.isEmpty {
                EmptyStateView(icon: "arrow.triangle.branch", message: "Select two branches", detail: "Choose a base and a target to compare their commits and files.")
            } else if showsCommits && controller.snapshot != nil {
                HSplitView {
                    ReferenceComparisonCommitsView(controller: controller, targetSide: false)
                    ReferenceComparisonCommitsView(controller: controller, targetSide: true)
                }
            } else if controller.isLoading {
                ProgressView("Loading comparison…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = controller.error {
                EmptyStateView(icon: "exclamationmark.triangle", message: "Could not compare references", detail: error)
            } else {
                ReferenceComparisonFilesView(controller: controller)
            }
        }
        .onAppear { controller.reload() }
        .onDisappear { controller.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(controller.title, systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                Spacer()
                if !controller.isBranchComparison {
                    Text("\(controller.files.count) files changed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if controller.isLoading || controller.isLoadingPatch || controller.isLoadingBaseCommits || controller.isLoadingTargetCommits {
                    Button("Stop", systemImage: "stop.circle") { controller.cancel() }
                }
                Button("Refresh", systemImage: "arrow.clockwise") { controller.reload() }
                    .help("Reload from local references without fetching")
                Button("Close", systemImage: "xmark", action: onClose)
            }
            if controller.isBranchComparison {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        branchPicker(targetSide: false)
                        swapButton
                        branchPicker(targetSide: true)
                    }
                    VStack(alignment: .leading) {
                        branchPicker(targetSide: false)
                        HStack { swapButton; branchPicker(targetSide: true) }
                    }
                }
                Picker("Diff mode", selection: Binding(get: { controller.mode }, set: controller.setMode)) {
                    ForEach(ReferenceComparisonMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Text(controller.mode == .mergeBase
                     ? "Files show changes introduced by Target since the common ancestor."
                     : "Files show changes from the Base tree to the Target tree.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Text("Merge base: \(mergeBaseLabel)")
                        .help(controller.snapshot?.mergeBases.joined(separator: "\n") ?? "Not yet resolved")
                    if let snapshot = controller.snapshot {
                        Text("Target: \(snapshot.targetOnlyCount) ahead · \(snapshot.baseOnlyCount) behind Base")
                    } else {
                        Text("Target ahead / behind Base: —")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var swapButton: some View {
        Button("Swap", systemImage: "arrow.left.arrow.right") { controller.swap() }
            .disabled(controller.baseRef.isEmpty || controller.targetRef.isEmpty)
            .help("Swap Base and Target")
    }

    private func branchPicker(targetSide: Bool) -> some View {
        let ref = targetSide ? controller.targetRef : controller.baseRef
        return Picker(targetSide ? "Target" : "Base", selection: Binding(
            get: { targetSide ? controller.targetRef : controller.baseRef },
            set: { if targetSide { controller.setTarget($0) } else { controller.setBase($0) } }
        )) {
            Text("Select branch…").tag("")
            if !ref.isEmpty && !controller.branches.contains(where: { $0.ref == ref }) {
                Text(ComparisonBranch(ref: ref).label).tag(ref)
            }
            ForEach(controller.branches) { branch in
                Text(branch.label).tag(branch.ref)
            }
        }
    }

    private var mergeBaseLabel: String {
        guard let snapshot = controller.snapshot else { return "—" }
        if snapshot.mergeBases.isEmpty { return "None" }
        return snapshot.mergeBases.map { String($0.prefix(8)) }.joined(separator: ", ")
    }
}
