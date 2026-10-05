// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct PathComparisonHeaderView: View {
    let controller: ReferenceComparisonController
    @State private var revision = ""
    @State private var showsRevisionPicker = false
    @FocusState private var isSearchFocused: Bool

    private var matchingRevisions: [String] {
        (["HEAD"] + controller.revisions).filter {
            searchQuery.isEmpty || $0.localizedStandardContains(searchQuery)
        }
    }

    private var searchQuery: String {
        revision.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
                    Button {
                        revision = ""
                        showsRevisionPicker = true
                    } label: {
                        HStack {
                            Text(controller.baseRef).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .pointingHandCursor()
                    .accessibilityLabel("Base revision: \(controller.baseRef)")
                    .popover(isPresented: $showsRevisionPicker, arrowEdge: .bottom) {
                        revisionPicker
                    }
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

    private var revisionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search or enter commit, branch, or tag", text: $revision)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit {
                    if !searchQuery.isEmpty { choose(searchQuery) }
                }
                .accessibilityLabel("Search revisions")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !searchQuery.isEmpty && !matchingRevisions.contains(searchQuery) {
                        revisionOption(searchQuery, label: "Compare with \(searchQuery)")
                        Divider()
                    }
                    ForEach(matchingRevisions, id: \.self) { ref in
                        revisionOption(ref, label: ref)
                    }
                }
            }
            .frame(maxHeight: 280)
            Text("Select a revision, or enter a SHA or expression such as HEAD~1 and press Return.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 420)
        .onAppear { isSearchFocused = true }
    }

    private func revisionOption(_ ref: String, label: String) -> some View {
        Button { choose(ref) } label: {
            HStack {
                Text(label).lineLimit(1).truncationMode(.middle)
                Spacer()
                if ref == controller.baseRef {
                    Image(systemName: "checkmark")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
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
        showsRevisionPicker = false
        if ref == controller.baseRef { controller.reload() } else { controller.setBase(ref) }
    }
}
