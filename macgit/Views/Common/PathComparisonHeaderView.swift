// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct PathComparisonHeaderView: View {
    let controller: ReferenceComparisonController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(controller.path?.path ?? "", systemImage: controller.path?.isDirectory == true ? "folder" : "doc")
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base revision").font(.caption).foregroundStyle(.secondary)
                    SearchableReferencePicker(
                        title: "Base revision", selection: controller.baseRef,
                        options: ["HEAD"] + controller.revisions,
                        searchPrompt: "Search or enter commit, branch, or tag",
                        allowsCustomReference: true,
                        onSelect: choose)
                    Text(controller.snapshot.map { String($0.base.prefix(8)) } ?? "Resolving revision…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 25)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compare to").font(.caption).foregroundStyle(.secondary)
                    Text(controller.pathTarget?.label ?? controller.targetRef)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .textSelection(.enabled)
                    Text(targetDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var targetDetail: String {
        switch controller.pathTarget {
        case .workingTree:
            return "Staged and unstaged edits · Tracked files only"
        case .revision:
            return "Browsed revision" + (controller.snapshot.map { " · " + String($0.target.prefix(8)) } ?? "")
        case .index:
            return "Staged content only"
        case nil:
            return controller.targetRef
        }
    }

    private func choose(_ ref: String) {
        if ref == controller.baseRef { controller.reload() } else { controller.setBase(ref) }
    }
}
