// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct SearchableReferencePicker: View {
    let title: String
    let selection: String
    let options: [String]
    let searchPrompt: String
    var allowsCustomReference = false
    var referenceLabel: (String) -> String = { $0 }
    let onSelect: (String) -> Void

    @State private var search = ""
    @State private var isPresented = false
    @FocusState private var isSearchFocused: Bool

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [String] {
        options.filter { query.isEmpty || referenceLabel($0).localizedStandardContains(query) || $0.localizedStandardContains(query) }
    }

    var body: some View {
        Button {
            search = ""
            isPresented = true
        } label: {
            HStack {
                Text(selection.isEmpty ? "Select branch…" : referenceLabel(selection))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                Image(systemName: "chevron.down").font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .pointingHandCursor()
        .accessibilityLabel("\(title): \(selection.isEmpty ? "Not selected" : referenceLabel(selection))")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(searchPrompt, text: $search)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search \(title)")
                    .onSubmit {
                        if allowsCustomReference && !query.isEmpty {
                            choose(query)
                        } else if let exact = matches.first(where: { $0 == query || referenceLabel($0) == query }) {
                            choose(exact)
                        } else if matches.count == 1, let match = matches.first {
                            choose(match)
                        }
                    }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if allowsCustomReference && !query.isEmpty && !options.contains(query) {
                            option(query, label: "Compare with \(query)")
                            Divider()
                        }
                        ForEach(matches, id: \.self) { ref in
                            option(ref, label: referenceLabel(ref))
                        }
                        if matches.isEmpty && !allowsCustomReference {
                            Text(options.isEmpty ? "No branches available" : "No matching branches")
                                .foregroundStyle(.secondary).padding(8)
                        }
                    }
                }
                .frame(maxHeight: 280)
                if allowsCustomReference {
                    Text("Select a revision, or enter a SHA or expression such as HEAD~1 and press Return.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(width: 420)
            .onAppear { isSearchFocused = true }
        }
    }

    private func option(_ ref: String, label: String) -> some View {
        Button { choose(ref) } label: {
            HStack {
                Text(label).lineLimit(1).truncationMode(.middle)
                Spacer()
                if ref == selection { Image(systemName: "checkmark") }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(ref)
    }

    private func choose(_ ref: String) {
        isPresented = false
        onSelect(ref)
    }
}
