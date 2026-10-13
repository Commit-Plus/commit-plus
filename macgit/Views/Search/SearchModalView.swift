//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import SwiftUI

struct SearchModalView: View {
    private static let modalWidth: CGFloat = 640
    private static let maximumResultsHeight: CGFloat = 340

    @StateObject private var coordinator: SearchCoordinator
    @FocusState private var isSearchFieldFocused: Bool
    let onDismiss: () -> Void
    let onSelectFilter: (SearchFilter) -> Void
    let onSelect: (SearchAction) -> Void
    
    init(
        repositoryURL: URL,
        initialFilter: SearchFilter,
        onDismiss: @escaping () -> Void,
        onSelectFilter: @escaping (SearchFilter) -> Void,
        onSelect: @escaping (SearchAction) -> Void
    ) {
        self._coordinator = StateObject(
            wrappedValue: SearchCoordinator(
                repositoryURL: repositoryURL,
                selectedFilter: initialFilter
            )
        )
        self.onDismiss = onDismiss
        self.onSelectFilter = onSelectFilter
        self.onSelect = onSelect
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if showsResultSection {
                Divider()
                    .opacity(0.7)

                filterBar

                Divider()
                    .opacity(0.7)

                if coordinator.filteredResults.isEmpty {
                    filteredEmptyState
                } else {
                    resultsList
                        .frame(height: resultsListHeight)
                }

                footer
            }
        }
        .frame(width: Self.modalWidth)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(
            .regular.tint(Color(nsColor: .controlBackgroundColor).opacity(0.72)),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.28), radius: 28, x: 0, y: 14)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            coordinator.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            coordinator.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            if let result = coordinator.selectedResult() {
                onSelect(result.action)
            }
            return .handled
        }
        .onKeyPress(characters: .alphanumerics) { _ in
            .ignored
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            
            TextField("Search commits, files, branches, and tags…", text: $coordinator.query)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)

            if coordinator.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching")
            }
            
            if !coordinator.query.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill", action: coordinator.clear)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }

            Text("⌘⇧F")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(SearchFilter.allCases, id: \.self) { filter in
                filterChip(filter)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func filterChip(_ filter: SearchFilter) -> some View {
        let isSelected = coordinator.selectedFilter == filter

        return Button {
            coordinator.selectFilter(filter)
            onSelectFilter(filter)
        } label: {
            Text(filter.title)
                .font(.callout)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search \(filter.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(groupedResults) { section in
                        Section(header: sectionHeader(title: section.type.rawValue)) {
                            ForEach(section.results) { result in
                                Button {
                                    coordinator.selectedResultID = result.id
                                    onSelect(result.action)
                                } label: {
                                    SearchResultRow(
                                        result: result,
                                        isSelected: coordinator.selectedResultID == result.id
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(result.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: coordinator.selectedResultID) { _, newID in
                if let newID {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }
    
    private var filteredEmptyState: some View {
        ContentUnavailableView(
            "No \(coordinator.selectedFilter.title)",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("Try All or another filter.")
        )
        .frame(height: 120)
    }
    
    private var footer: some View {
        HStack {
            Text("↑↓ Navigate • ↵ Select")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("esc Close")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.thinMaterial)
    }
    
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.caption)
            .bold()
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
    
    private var groupedResults: [ResultSection] {
        let typeOrder: [SearchResultType] = [.commit, .file, .branch, .tag]
        return typeOrder.compactMap { type in
            let typeResults = coordinator.filteredResults.filter { $0.type == type }
            guard !typeResults.isEmpty else { return nil }
            return ResultSection(type: type, results: typeResults)
        }
    }

    private var showsResultSection: Bool {
        !coordinator.results.isEmpty
    }

    private var resultsListHeight: CGFloat {
        let rowsHeight = CGFloat(coordinator.filteredResults.count) * 44
        let headersHeight = CGFloat(groupedResults.count) * 28
        return min(Self.maximumResultsHeight, rowsHeight + headersHeight + 16)
    }
}

struct ResultSection: Identifiable {
    var id: String { type.rawValue }
    let type: SearchResultType
    let results: [SearchResult]
}
