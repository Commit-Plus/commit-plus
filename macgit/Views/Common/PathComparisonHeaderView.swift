// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct PathComparisonHeaderView: View {
    let controller: ReferenceComparisonController
    @State private var revision = "HEAD"

    private var matchingRevisions: [String] {
        controller.revisions.filter { revision.isEmpty || revision == "HEAD" || $0.localizedStandardContains(revision) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(controller.path?.path ?? "")
                .font(.callout.monospaced())
                .textSelection(.enabled)
            HStack {
                TextField("Commit, branch, or tag", text: $revision)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(compare)
                    .accessibilityLabel("Base revision")
                Menu("Choose Revision") {
                    Button("HEAD") { choose("HEAD") }
                    ForEach(matchingRevisions, id: \.self) { ref in
                        Button(ref) { choose(ref) }
                    }
                }
                Button("Compare", action: compare)
                    .disabled(revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Left: \(controller.baseRef)\(baseHash)  →  Right: \(controller.pathTarget?.label ?? controller.targetRef)\(targetHash)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if controller.pathTarget == .workingTree {
                Text("Current tracked-file content, including staged and unstaged edits. Untracked files are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { revision = controller.baseRef }
    }

    private var baseHash: String {
        controller.snapshot.map { " (\($0.base.prefix(8)))" } ?? ""
    }

    private var targetHash: String {
        guard case .revision = controller.pathTarget, let snapshot = controller.snapshot else { return "" }
        return " (\(snapshot.target.prefix(8)))"
    }

    private func choose(_ ref: String) {
        revision = ref
        compare()
    }

    private func compare() {
        let ref = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        if ref == controller.baseRef { controller.reload() } else { controller.setBase(ref) }
    }
}
