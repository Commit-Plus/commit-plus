//
//  BranchFilterBar.swift
//  macgit
//

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

struct BranchFilterBar: View {
    let repositoryURL: URL
    @Binding var selectedFilter: HistoryBranchFilter
    @Binding var includeRemotes: Bool
    @Binding var onlyThisBranch: Bool
    @Binding var baseBranch: String?
    @Binding var searchText: String

    @State private var localBranches: [String] = []
    @State private var remoteBranches: [String] = []
    @State private var isShowingBranchList = false
    @State private var isLoadingLocalBranches = false
    @State private var isLoadingRemoteBranches = false
    @State private var currentBranchName: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            filterRow(includesComparison: showsComparison)
            VStack(alignment: .leading, spacing: 0) {
                filterRow(includesComparison: false)
                if showsComparison {
                    HStack {
                        comparisonPicker
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 8)
                    .frame(height: 28)
                }
            }
        }
        .padding(.trailing, 16)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
        .task(id: repositoryURL.standardizedFileURL) {
            await loadLocalBranches()
        }
        .task(id: isShowingBranchList) {
            guard isShowingBranchList else { return }
            await loadLocalBranches()
        }
        .task(id: remoteLoadKey) {
            guard includeRemotes else { return }
            await loadRemoteBranches()
        }
        .onChange(of: selectedFilter) { _, _ in
            updateComparisonBase()
        }
        .onChange(of: onlyThisBranch) { _, _ in
            updateComparisonBase()
        }
        .onChange(of: includeRemotes) { _, isIncluded in
            guard !isIncluded else { return }

            if case .branch(let branch) = selectedFilter,
               remoteBranches.contains(branch),
               !localBranches.contains(branch) {
                selectedFilter = .current
            }
            updateComparisonBase()

            Task {
                await loadLocalBranches()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            guard let url = notification.userInfo?["repositoryURL"] as? URL,
                  url == repositoryURL else {
                return
            }
            Task {
                await reloadBranches()
            }
        }
    }

    private var showsComparison: Bool {
        onlyThisBranch && selectedFilter != .all
    }

    private func filterRow(includesComparison: Bool) -> some View {
        HStack(spacing: 10) {
                Button(action: toggleBranchList) {
                    HStack(spacing: 6) {
                        Text(selectedFilterTitle)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .frame(width: 220)
                .padding(.leading, 8)
                .popover(isPresented: $isShowingBranchList, arrowEdge: .bottom) {
                    branchList
                }

                Toggle("Include Remotes", isOn: $includeRemotes)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                Toggle("Only this branch", isOn: $onlyThisBranch)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .disabled(selectedFilter == .all)
                    .help("Show commits in the selected branch that are not in the comparison base.")

                if includesComparison { comparisonPicker }

                Spacer(minLength: 12)

                HistoryFilterSearchField(searchText: $searchText)
            }
            .frame(height: 28)

    }

    private var comparisonPicker: some View {
        HStack(spacing: 6) {
            Text("Compared with").font(.caption).foregroundStyle(.secondary).fixedSize()
            SearchableReferencePicker(
                title: "Compared with", selection: baseBranch ?? "",
                options: comparisonBranches, searchPrompt: "Search branches",
                placeholder: "Choose base…", clearSelectionTitle: "Choose base…",
                onSelect: { baseBranch = $0.isEmpty ? nil : $0 })
        }
        .frame(width: 300)
        .help("The suggested base is a comparison target; Git does not record the original parent branch.")
    }

    private var branchList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    branchButton(
                        title: "All Branches",
                        systemImage: "arrow.triangle.branch",
                        filter: .all
                    )

                    branchButton(
                        title: "Current Branch",
                        systemImage: "arrow.triangle.branch",
                        filter: .current
                    )

                    Divider()
                        .padding(.vertical, 4)

                    branchSectionTitle("Local Branches")

                    if isLoadingLocalBranches && localBranches.isEmpty {
                        loadingRow("Loading local branches…")
                    } else if localBranches.isEmpty {
                        Text("No local branches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(localBranches, id: \.self) { branch in
                            branchButton(
                                title: branch,
                                systemImage: "arrow.triangle.branch",
                                filter: .branch(branch)
                            )
                        }
                    }

                    if includeRemotes {
                        Divider()
                            .padding(.vertical, 4)

                        branchSectionTitle("Remote Branches")

                        if isLoadingRemoteBranches && remoteBranches.isEmpty {
                            loadingRow("Loading remote branches…")
                        } else if remoteBranches.isEmpty {
                            Text("No remote branches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(remoteBranches, id: \.self) { branch in
                                branchButton(
                                    title: branch,
                                    systemImage: "cloud",
                                    filter: .branch(branch)
                                )
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(width: 300, height: 340)
        }
    }

    private func branchSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private func branchButton(
        title: String,
        systemImage: String,
        filter: HistoryBranchFilter
    ) -> some View {
        Button {
            selectedFilter = filter
            isShowingBranchList = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if selectedFilter == filter {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadingRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var remoteLoadKey: String {
        "\(repositoryURL.standardizedFileURL.path)|\(includeRemotes)"
    }

    private var selectedFilterTitle: String {
        switch selectedFilter {
        case .all:
            return "All Branches"
        case .current:
            return "Current Branch"
        case .branch(let branch):
            return branch
        }
    }

    private func toggleBranchList() {
        isShowingBranchList.toggle()
    }

    private func loadLocalBranches() async {
        isLoadingLocalBranches = true
        defer {
            isLoadingLocalBranches = false
            validateSelectedBranch()
        }

        let branches = await GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
        currentBranchName = await GitStatusService.shared.currentBranch(in: repositoryURL)
        localBranches = branches.sorted(by: Self.compareBranchNames)
        updateComparisonBase()
    }

    private func loadRemoteBranches() async {
        isLoadingRemoteBranches = true
        defer {
            isLoadingRemoteBranches = false
            validateSelectedBranch()
        }

        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        let branches = await withTaskGroup(of: [String].self, returning: [String].self) { group in
            for remote in remotes {
                group.addTask {
                    let branches = await GitStatusService.shared.cachedRemoteBranches(
                        remote: remote,
                        in: repositoryURL
                    )
                    return branches.compactMap { branch in
                        guard branch != "HEAD", !branch.hasPrefix("HEAD -> ") else {
                            return nil
                        }
                        return "\(remote)/\(branch)"
                    }
                }
            }

            var result: [String] = []
            for await branches in group {
                result.append(contentsOf: branches)
            }
            return result
        }

        guard includeRemotes else { return }
        remoteBranches = Array(Set(branches)).sorted(by: Self.compareBranchNames)
        updateComparisonBase()
    }

    private func reloadBranches() async {
        async let localLoad: Void = loadLocalBranches()
        async let remoteLoad: Void = includeRemotes ? loadRemoteBranches() : ()
        _ = await (localLoad, remoteLoad)
    }

    private static func compareBranchNames(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func validateSelectedBranch() {
        guard !isLoadingLocalBranches,
              !includeRemotes || !isLoadingRemoteBranches else {
            return
        }
        guard case .branch(let branch) = selectedFilter else { return }
        let isAvailable = localBranches.contains(branch)
            || (includeRemotes && remoteBranches.contains(branch))
        if !isAvailable {
            selectedFilter = .current
        }
    }

    private var targetBranch: String? {
        switch selectedFilter {
        case .all: nil
        case .current: currentBranchName
        case .branch(let branch): branch
        }
    }

    private var comparisonBranches: [String] {
        Array(Set(localBranches + (includeRemotes ? remoteBranches : [])))
            .filter { $0 != targetBranch }
            .sorted(by: Self.compareBranchNames)
    }

    private func updateComparisonBase() {
        guard selectedFilter != .all else { return }
        let available = comparisonBranches
        if let baseBranch, available.contains(baseBranch) { return }
        // Offer familiar integration branches, without claiming to infer the
        // branch's creation point. Other repositories require an explicit choice.
        baseBranch = ["main", "master", "develop", "origin/main", "origin/master"]
            .first { available.contains($0) }
    }
}

struct ColumnResizer: View {
    @Binding var leftWidth: CGFloat
    @Binding var rightWidth: CGFloat
    var minimumLeftWidth: CGFloat = 40
    @State private var initialLeftWidth: CGFloat?
    @State private var initialRightWidth: CGFloat?
    @State private var dragHasRightColumn = false

    /// Whether the right side is a real column (true) or empty space (false)
    private var hasRightColumn: Bool { rightWidth > 10 }

    static func committedWidths(
        initialLeft: CGFloat,
        initialRight: CGFloat,
        translation: CGFloat,
        hasRightColumn: Bool,
        minimumLeftWidth: CGFloat = 40
    ) -> (left: CGFloat, right: CGFloat) {
        let minimumRightWidth: CGFloat = 40

        if hasRightColumn {
            // Standard two-column resizer: space moves from right to left.
            let maxExpand = initialRight - minimumRightWidth
            let actualDelta = max(-(initialLeft - minimumLeftWidth), min(translation, maxExpand))
            return (
                left: initialLeft + actualDelta,
                right: initialRight - actualDelta
            )
        } else {
            // Last resizer: only clamp left column minimum.
            let actualDelta = max(-(initialLeft - minimumLeftWidth), translation)
            return (
                left: initialLeft + actualDelta,
                right: initialRight
            )
        }
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if initialLeftWidth == nil {
                            initialLeftWidth = leftWidth
                            initialRightWidth = rightWidth
                            dragHasRightColumn = hasRightColumn
                        }

                        guard let initialLeftWidth,
                              let initialRightWidth else {
                            return
                        }

                        let resizedWidths = Self.committedWidths(
                            initialLeft: initialLeftWidth,
                            initialRight: initialRightWidth,
                            translation: value.translation.width,
                            hasRightColumn: dragHasRightColumn,
                            minimumLeftWidth: minimumLeftWidth
                        )
                        leftWidth = resizedWidths.left
                        rightWidth = resizedWidths.right
                    }
                    .onEnded { _ in
                        initialLeftWidth = nil
                        initialRightWidth = nil
                    }
            )
            .overlay(
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            )
    }
}
